import Vapor

@WebSocketActor
public protocol AnyObserver: AnyObject, Swift.Sendable, Broadcastable, CustomStringConvertible, Disconnectable, WebSocketSendable, Loggable {
    nonisolated var key: String { get }
    nonisolated var path: String { get }
    
    nonisolated var application: Application { get }
    nonisolated var eventLoop: EventLoop { get }
    var clients: [AnyClient] { get }
    var encoder: Encoder? { get set }
    var decoder: Decoder? { get set }
    nonisolated var exchangeMode: ExchangeMode { get }
    
    nonisolated init (app: Application, key: String, path: String, exchangeMode: ExchangeMode)
    
    func setup()
    
    func on(open client: AnyClient)
    func on(close client: AnyClient)
    func on(ping client: AnyClient)
    func on(pong client: AnyClient)
    func on(text: String, client: AnyClient)
    func on(byteBuffer: ByteBuffer, client: AnyClient)
    func on(data: Data, client: AnyClient)
}

internal protocol _AnyObserver: AnyObserver, _Disconnectable, _WebSocketSendable {
    var _clients: [_AnyClient] { get set }
    var _encoder: Encoder { get }
    var _decoder: Decoder { get }
    
    func initialize(encoder: (any Encoder)?, decoder: (any Decoder)?)

    func _on(open client: _AnyClient)
    func _on(close client: _AnyClient)
    func _on(ping client: _AnyClient)
    func _on(pong client: _AnyClient)
    func _on(text: String, client: _AnyClient)
    func _on(byteBuffer: ByteBuffer, client: _AnyClient)
    func _on(data: Data, client: _AnyClient)
}

// MARK: - Default implementation

extension AnyObserver {
    nonisolated public var eventLoop: EventLoop { application.ws.knownEventLoop }
   
    var _encoder: Encoder {
        if let encoder = self.encoder {
            return encoder
        }
        if let encoder = application.ws.encoder {
            return encoder
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DefaultDateFormatter.make())
        return encoder
    }
    
    var _decoder: Decoder {
        if let decoder = self.decoder {
            return decoder
        }
        if let decoder = application.ws.decoder {
            return decoder
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(DefaultDateFormatter.decode)
        return decoder
    }
    
    nonisolated func handle(
        _ req: Request,
        _ ws: WebSocketKit.WebSocket,
        encoder: (any Encoder)?,
        decoder: (any Decoder)?
    ) {
        guard let self = self as? any _AnyObserver else { return }
        self.handle(req, ws, encoder: encoder, decoder: decoder)
    }
    
    /// See `Broadcastable`
    
    public var broadcast: Broadcaster {
        .init(eventLoop: eventLoop,
               clients: clients,
               exchangeMode: exchangeMode,
               logger: application.logger,
               encoder: encoder,
               defaultEncoder: application.ws.encoder)
    }
    
    /// see `CustomStringConvertible`
    nonisolated public var description: String {
        "\(String(describing: Self.self))(key: \"\(key)\", at: \"\(path)\")"
    }
}

extension _AnyObserver {
    var clients: [AnyClient] { _clients }
    nonisolated var observer: _AnyObserver { self }
    var sockets: [WebSocket] { _clients.flatMap { $0.sockets } }
    
    /// Only the actor consumer touches client state; callbacks enqueue events in wire order.
    nonisolated func handle(
        _ req: Request,
        _ ws: WebSocketKit.WebSocket,
        encoder: (any Encoder)?,
        decoder: (any Decoder)?
    ) {
        let (events, continuation) = AsyncStream<InboundEvent>.makeStream()
        ws.onText { _, text in continuation.yield(.text(text)) }
        ws.onBinary { _, buffer in continuation.yield(.binary(buffer)) }
        ws.onPing { _, _ in continuation.yield(.ping) }
        ws.onPong { _, _ in continuation.yield(.pong) }
        ws.onClose.whenComplete { _ in continuation.finish() }

        Task { @WebSocketActor in
            initialize(encoder: encoder, decoder: decoder)
            let client = Client(self, req, ws, logger: logger)
            _clients.append(client)
            _on(open: client)
            on(open: client)
            logger.info("[⚡️] 🟢 new connection \(client.id)")

            for await event in events {
                switch event {
                case .ping:
                    _on(ping: client)
                    on(ping: client)
                case .pong:
                    _on(pong: client)
                    on(pong: client)
                case .text(let text):
                    guard exchangeMode != .binary else {
                        logger.warning("[⚡️] Incoming text rejected in binary mode")
                        continue
                    }
                    _on(text: text, client: client)
                    on(text: text, client: client)
                case .binary(let buffer):
                    guard exchangeMode != .text else {
                        logger.warning("[⚡️] Incoming binary data rejected in text mode")
                        continue
                    }
                    _on(byteBuffer: buffer, client: client)
                    on(byteBuffer: buffer, client: client)
                    guard buffer.readableBytes > 0 else { continue }
                    let data = Data(buffer.readableBytesView)
                    _on(data: data, client: client)
                    on(data: data, client: client)
                }
            }

            _clients.removeAll { $0 === client }
            logger.info("[⚡️] 🔴 connection closed \(client.id)")
            _on(close: client)
            on(close: client)
        }
    }

    public func on(open client: AnyClient) {}
    public func on(close client: AnyClient) {}
    public func on(ping client: AnyClient) {}
    public func on(pong client: AnyClient) {}
    public func on(text: String, client: AnyClient) {}
    public func on(byteBuffer: ByteBuffer, client: AnyClient) {}
    public func on(data: Data, client: AnyClient) {}
    
    func _on(open client: _AnyClient) {}
    func _on(close client: _AnyClient) {}
    func _on(ping client: _AnyClient) {}
    func _on(pong client: _AnyClient) {}
    func _on(text: String, client: _AnyClient) {}
    func _on(byteBuffer: ByteBuffer, client: _AnyClient) {}
    func _on(data: Data, client: _AnyClient) {}
}

private enum InboundEvent: Swift.Sendable {
    case text(String)
    case binary(ByteBuffer)
    case ping
    case pong
}
