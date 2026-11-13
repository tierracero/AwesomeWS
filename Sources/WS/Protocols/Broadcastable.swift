import Foundation
import NIO

@WebSocketActor
public protocol Broadcastable {
    var broadcast: Broadcaster { get }
}
