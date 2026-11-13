import WebSocketKit
import Logging
import Foundation
import NIOWebSocket

@WebSocketActor
public final class Broadcaster: Disconnectable, _Disconnectable, WebSocketSendable, _WebSocketSendable, Subscribable {
    let eventLoop: EventLoop
    var clients: [AnyClient]
    let exchangeMode: ExchangeMode
    nonisolated let logger: Logger
    var encoder: Encoder?
    let defaultEncoder: Encoder?
    
    var _encoder: Encoder {
        if let encoder = self.encoder {
            return encoder
        }
        if let encoder = self.defaultEncoder {
            return encoder
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DefaultDateFormatter.make())
        return encoder
    }
    
    var excludedClients: Set<UUID> = []
    
    init (eventLoop: EventLoop, clients: [AnyClient], exchangeMode: ExchangeMode, logger: Logger, encoder: Encoder?, defaultEncoder: Encoder?) {
        self.eventLoop = eventLoop
        self.clients = clients
        self.exchangeMode = exchangeMode
        self.logger = logger
        self.encoder = encoder
        self.defaultEncoder = defaultEncoder
    }
    
    /// Set custom data encoder
    public func encoder(_ encoder: Encoder) -> Self {
        self.encoder = encoder
        return self
    }
    
    /// Filtered clients
    private var filteredClients: [AnyClient] {
        clients.filter { client in
            !excludedClients.contains { $0 == client.id }
        }
    }
    
    /// Cached filtered sockets
    var cachedSockets: [WebSocket]?
    
    /// Filtered sockets
    var sockets: [WebSocket] {
        if let cachedSockets = cachedSockets {
            return cachedSockets
        }
        let sockets = filteredClients.map { $0.socket }
        cachedSockets = sockets
        return sockets
    }
    
    /// Quantity of filtered sockets
    public var count: Int { cachedSockets?.count ?? sockets.count }
    
    /// Excludes provided clients from broadcast
    public func exclude(_ clients: AnyClient...) -> Self {
        exclude(clients)
    }
    
    /// Exclude provided clients from recipients
    public func exclude(_ clients: [AnyClient]) -> Self {
        cachedSockets = nil
        clients.forEach {
            excludedClients.insert($0.id)
        }
        return self
    }
    
    /// Filter recipients by closure result
    public func filter(_ filter: @escaping (AnyClient) -> Bool) -> Self {
        clients.removeAll { !filter($0) }
        return self
    }
    
    /// Filter recipients by asynchronously evaluated predicate.
    public func filter(_ predicate: (AnyClient) async throws -> Bool) async throws -> Broadcaster {
        var retained: [AnyClient] = []
        for client in clients {
            if try await predicate(client) {
                retained.append(client)
            }
        }
        clients = retained
        cachedSockets = nil
        return self
    }

    /// Filter recipients by provided channels
    public func channels(_ channels: String...) -> Self {
        self.channels(channels)
    }
    
    /// Filter recipients by provided channels
    public func channels(_ channels: [String]) -> Self {
        clients.removeAll {
            !$0.channels.contains(where: channels.contains)
        }
        return self
    }
    
    /// Subscribe filtered clients to channels.
    public func subscribe(to channels: [String]) async throws {
        for client in clients {
            try await client.subscribe(to: channels)
        }
    }

    /// Unsubscribe filtered clients from channels.
    public func unsubscribe(from channels: [String]) async throws {
        for client in clients {
            try await client.unsubscribe(from: channels)
        }
    }

    public func disconnect() async throws {
        try await _disconnect()
    }

    public func disconnect(code: WebSocketErrorCode) async throws {
        try await _disconnect(code: code)
    }

    public func send<S>(text: S) async where S: Collection, S.Element == Character {
        _send(text: text)
    }

    public func send(bytes: [UInt8]) async {
        _send(bytes: bytes)
    }

    public func send<Data>(data: Data) async where Data: DataProtocol {
        _send(data: data)
    }

    public func send<Data>(data: Data, opcode: WebSocketOpcode) async where Data: DataProtocol {
        _send(data: data, opcode: opcode)
    }

    public func send<C>(model: C) async throws where C: Encodable {
        try _send(model: model)
    }

    public func send<C>(model: C, encoder: Encoder) async throws where C: Encodable {
        try _send(model: model, encoder: encoder)
    }

    public func send<T: Codable>(event: EID<T>) async throws {
        try _send(event: event)
    }

    public func send<T: Codable>(event: EID<T>, payload: T?) async throws {
        try _send(event: event, payload: payload)
    }

    public func sendPing() async {
        _sendPing()
    }
}
