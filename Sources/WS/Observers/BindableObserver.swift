import Foundation
import Vapor
import NIOWebSocket

open class BindableObserver: BaseObserver, Bindable, _Bindable {
    var binds: [String : BindHandler] = [:]
    
    public func bind<P>(_ identifier: EID<P>, _ handler: @escaping @WebSocketActor @Sendable (AnyClient) -> Void) where P: Codable {
        _bind(identifier, handler)
    }
    
    public func bindOptional<P>(_ identifier: EID<P>, _ handler: @escaping @WebSocketActor @Sendable (AnyClient, P?) -> Void) where P : Codable {
        _bindOptional(identifier, handler)
    }
    
    public func bind<P>(_ identifier: EID<P>, _ handler: @escaping @WebSocketActor @Sendable (AnyClient, P) -> Void) where P : Codable {
        _bind(identifier, handler)
    }
}

extension BindableObserver {
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
