import Vapor
import NIOWebSocket

@WebSocketActor
public protocol Subscribable {
    func subscribe(to channels: String...) async throws
    func subscribe(to channels: [String]) async throws
    func unsubscribe(from channels: String...) async throws
    func unsubscribe(from channels: [String]) async throws
}

extension Subscribable {
    public func subscribe(to channels: String...) async throws {
        try await subscribe(to: channels)
    }

    public func unsubscribe(from channels: String...) async throws {
        try await unsubscribe(from: channels)
    }
}

@WebSocketActor
internal protocol _Subscribable: AnyObject, Subscribable {
    var eventLoop: EventLoop { get }
    var clients: [_AnyClient] { get }
}

extension _Subscribable {
    public func subscribe(to channels: [String]) async throws {
        for client in clients {
            client.channels.formUnion(channels)
        }
    }

    public func unsubscribe(from channels: [String]) async throws {
        for client in clients {
            client.channels.subtract(channels)
        }
    }
}
