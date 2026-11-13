import Vapor
import NIOWebSocket

@WebSocketActor
public protocol Disconnectable {
    func disconnect() async throws
    func disconnect(code: WebSocketErrorCode) async throws
}

@WebSocketActor
internal protocol _Disconnectable: Disconnectable {
    var sockets: [WebSocket] { get }
}

extension _Disconnectable {
    public func disconnect() async throws {
        try await _disconnect()
    }

    public func disconnect(code: WebSocketErrorCode) async throws {
        try await _disconnect(code: code)
    }

    func _disconnect() async throws {
        try await _disconnect(code: .goingAway)
    }

    func _disconnect(code: WebSocketErrorCode) async throws {
        for socket in sockets {
            try await socket.close(code: code).get()
        }
    }
}
