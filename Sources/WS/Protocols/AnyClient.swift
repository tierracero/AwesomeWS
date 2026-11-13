import Foundation
import Vapor
import NIOWebSocket

@WebSocketActor
public protocol AnyClient: Swift.Sendable, Broadcastable, Disconnectable, Subscribable, WebSocketSendable {
    nonisolated var id: UUID { get }
    nonisolated var application: Application { get }
    nonisolated var eventLoop: EventLoop { get }
    nonisolated var originalRequest: Request { get }
    var channels: Set<String> { get }
    nonisolated var socket: WebSocket { get }
    nonisolated var observer: AnyObserver { get }
}

internal protocol _AnyClient: AnyClient, _Disconnectable, _Subscribable, _WebSocketSendable {
    var _observer: _AnyObserver { get }
    var channels: Set<String> { get set }
}

extension AnyClient {
    nonisolated public var eventLoop: EventLoop { application.ws.knownEventLoop }
    nonisolated public var logger: Logger { application.logger }
    
    /// See `Broadcastable`
    public var broadcast: Broadcaster {
        observer.broadcast
    }
}

extension _AnyClient {
    public var exchangeMode: ExchangeMode { observer.exchangeMode }
    var _encoder: Encoder { observer._encoder }
}
