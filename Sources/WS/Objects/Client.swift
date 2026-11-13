import Foundation
import Vapor
import NIOWebSocket

@WebSocketActor
final class Client: _AnyClient {
    /// See `AnyClient`
    nonisolated public let id: UUID = .init()
    nonisolated public let originalRequest: Request
    nonisolated public let application: Application
    
    /// See `Loggable`
    nonisolated public let logger: Logger
    
    /// See `_WebSocketSendable`
    nonisolated let observer: AnyObserver
    nonisolated let _observer: _AnyObserver
    nonisolated let socket: WebSocketKit.WebSocket
    var sockets: [WebSocket] { [socket] }
    
    /// See `AnyClient`
    public internal(set) var channels: Set<String> = []
    
    /// See `Subscribable`
    var clients: [_AnyClient] { [self] }
    
    init (_ observer: _AnyObserver, _ request: Vapor.Request, _ socket: WebSocketKit.WebSocket, logger: Logger) {
        self.observer = observer
        self._observer = observer
        self.originalRequest = request
        self.application = request.application
        self.logger = logger
        self.socket = socket
    }
}

extension Client {
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
