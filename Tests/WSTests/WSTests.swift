import Foundation
import Testing
import Vapor
import WebSocketKit
import NIOCore
import NIOEmbedded
import NIOWebSocket
@testable import WS

@Suite("WebSocket actor isolation", .timeLimit(.minutes(1)))
struct WSTests {
    @Test func registryIsSharedAcrossConcurrentLookups() async throws {
        try await withApplication { app in
            let registry = app.wsStorage
            let references = await withTaskGroup(of: _Storage.self, returning: [_Storage].self) { group in
                for _ in 0..<100 { group.addTask { app.wsStorage } }
                var values: [_Storage] = []
                for await value in group { values.append(value) }
                return values
            }
            #expect(references.count == 100)
            #expect(references.allSatisfy { $0 === registry })

            let id = WSID<RecordingObserver>("recording")
            let observer = app.ws.build(id).serve()
            app.ws.setDefault(id)
            #expect(app.ws.observer(id) === observer)
            #expect(app.ws.observer() === observer)
            let replacement = RecordingObserver(app: app, key: id.key, path: "/", exchangeMode: .text)
            registry[id.key] = replacement
            #expect(app.ws.observer(id) === observer)
        }
    }

    @Test func bootPreparesExactlyOnceAndBuilderCodecWins() async throws {
        try await withApplication { app in
            let observer = app.ws.build(WSID<RecordingObserver>("boot"))
                .encoder(MarkerEncoder(marker: "builder"))
                .serve()
            try await app.asyncBoot()
            await observer.initialize(encoder: nil, decoder: nil)
            let snapshot = await observer.snapshot()
            #expect(snapshot.events == ["setup"])
            #expect(snapshot.encoder == "builder")
        }
    }

    @Test func bufferedFramesRetainOrderAndCloseRemovesClient() async throws {
        try await withApplication { app in
            let fixture = try await connection(app: app, mode: .both)
            for number in 0..<32 {
                try await fixture.channel.writeInbound(WebSocketFrame(
                    fin: true, opcode: .text, data: ByteBuffer(string: "message-\(number)")
                ))
                try await fixture.channel.writeInbound(WebSocketFrame(
                    fin: true, opcode: .binary, data: ByteBuffer(bytes: [UInt8(number)])
                ))
            }
            try await fixture.channel.close().get()
            let events = await fixture.observer.waitForClose()
            var expected = ["setup", "open"]
            for number in 0..<32 {
                expected += ["message-\(number)", "buffer-1", "data-1"]
            }
            expected.append("close")
            #expect(events == expected)
            let clients = await fixture.observer.clients
            #expect(clients.isEmpty)
        }
    }

    @Test(arguments: [ExchangeMode.text, .binary])
    func exchangeModeRejectsWrongFrameType(mode: ExchangeMode) async throws {
        try await withApplication { app in
            let fixture = try await connection(app: app, mode: mode)
            try await fixture.channel.writeInbound(WebSocketFrame(
                fin: true, opcode: .text, data: ByteBuffer(string: "text")
            ))
            try await fixture.channel.writeInbound(WebSocketFrame(
                fin: true, opcode: .binary, data: ByteBuffer(bytes: [1, 2])
            ))
            try await fixture.channel.close().get()
            let events = await fixture.observer.waitForClose()
            #expect(events == (mode == .text
                ? ["setup", "open", "text", "close"]
                : ["setup", "open", "buffer-2", "data-2", "close"]))
        }
    }

    @Test func concurrentChannelUpdatesDoNotLoseMembership() async throws {
        try await withApplication { app in
            let fixture = try await connection(app: app, mode: .text)
            let client = fixture.client
            try await withThrowingTaskGroup(of: Void.self) { group in
                for number in 0..<100 {
                    group.addTask { try await client.subscribe(to: "channel-\(number)") }
                }
                try await group.waitForAll()
            }
            let channels = await client.channels
            #expect(channels == Set((0..<100).map { "channel-\($0)" }))
            try await withThrowingTaskGroup(of: Void.self) { group in
                for number in 0..<100 {
                    group.addTask { try await client.unsubscribe(from: "channel-\(number)") }
                }
                try await group.waitForAll()
            }
            let remaining = await client.channels
            #expect(remaining.isEmpty)
            try await fixture.channel.close().get()
            _ = await fixture.observer.waitForClose()
        }
    }

    @Test(arguments: [ExchangeMode.text, .binary, .both])
    func outgoingEventsKeepEnvelopeAndExchangeMode(mode: ExchangeMode) async throws {
        try await withApplication { app in
            let fixture = try await connection(app: app, mode: mode)
            let message = Message(value: "hello")
            try await fixture.client.send(event: EID<Message>("message"), payload: message)
            let expectedOpcodes: [WebSocketOpcode] = mode == .text ? [.text]
                : mode == .binary ? [.binary] : [.binary, .text]
            for opcode in expectedOpcodes {
                let frame = try await fixture.channel.waitForOutboundWrite(as: WebSocketFrame.self)
                #expect(frame.opcode == opcode)
                let envelope = try JSONDecoder().decode(
                    Envelope.self, from: Data(frame.data.readableBytesView)
                )
                #expect(envelope == Envelope(event: "message", payload: message))
            }
            try await fixture.channel.close().get()
            _ = await fixture.observer.waitForClose()
        }
    }

    @Test func defaultDateCodecKeepsAcceptedFormats() throws {
        struct Value: Codable { let date: Date }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(DefaultDateFormatter.decode)
        for input in [
            "2026-11-12T00:00:00",
            "2026-11-12T00:00:00.123456",
            "2026-11-12T00:00:00Z",
            "2026-11-12T00:00:00.123456Z"
        ] {
            _ = try decoder.decode(Value.self, from: Data("{\"date\":\"\(input)\"}".utf8))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DefaultDateFormatter.make())
        let data = try encoder.encode(Value(date: Date(timeIntervalSince1970: 0)))
        #expect(String(decoding: data, as: UTF8.self) == "{\"date\":\"1970-01-01T00:00:00Z\"}")
    }
}

private func withApplication<T: Sendable>(
    _ body: @Sendable (Application) async throws -> T
) async throws -> T {
    let app = try await Application.make(.testing)
    do {
        let result = try await body(app)
        try await app.asyncShutdown()
        return result
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
}

private struct Fixture: Sendable {
    let observer: RecordingObserver
    let channel: NIOAsyncTestingChannel
    let client: any AnyClient
}

private func connection(app: Application, mode: ExchangeMode) async throws -> Fixture {
    let channel = NIOAsyncTestingChannel()
    try await channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 80)).get()
    let observer = RecordingObserver(app: app, key: UUID().uuidString, path: "/ws", exchangeMode: mode)
    let request = Request(application: app, on: channel.eventLoop)
    try await channel.eventLoop.flatSubmit {
        WebSocket.server(on: channel) { socket in
            observer.handle(request, socket, encoder: nil, decoder: nil)
        }
    }.get()
    let client = await observer.waitForOpen()
    return Fixture(observer: observer, channel: channel, client: client)
}

@WebSocketActor
private final class RecordingObserver: ClassicObserver {
    private var events: [String] = []
    private var currentClient: (any AnyClient)?
    private var didClose = false
    private var openWaiters: [CheckedContinuation<any AnyClient, Never>] = []
    private var closeWaiters: [CheckedContinuation<[String], Never>] = []

    func waitForOpen() async -> any AnyClient {
        if let currentClient { return currentClient }
        return await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitForClose() async -> [String] {
        if didClose { return events }
        return await withCheckedContinuation { closeWaiters.append($0) }
    }

    override func setup() {
        events.append("setup")
        encoder = MarkerEncoder(marker: "setup")
    }
    override func on(open client: any AnyClient) {
        events.append("open")
        currentClient = client
        for waiter in openWaiters { waiter.resume(returning: client) }
        openWaiters.removeAll()
    }
    override func on(text: String, client: any AnyClient) { events.append(text) }
    override func on(byteBuffer: ByteBuffer, client: any AnyClient) {
        events.append("buffer-\(byteBuffer.readableBytes)")
    }
    override func on(data: Data, client: any AnyClient) { events.append("data-\(data.count)") }
    override func on(close client: any AnyClient) {
        events.append("close")
        didClose = true
        currentClient = nil
        for waiter in closeWaiters { waiter.resume(returning: events) }
        closeWaiters.removeAll()
    }
    func snapshot() -> (events: [String], encoder: String?) {
        (events, (encoder as? MarkerEncoder)?.marker)
    }
}

private struct MarkerEncoder: WS.Encoder {
    let marker: String
    func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}

private struct Message: Codable, Equatable, Sendable {
    let value: String
}

private struct Envelope: Codable, Equatable, Sendable {
    let event: String
    let payload: Message
}
