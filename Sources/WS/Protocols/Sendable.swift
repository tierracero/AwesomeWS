import Vapor
import NIOWebSocket

@WebSocketActor
public protocol WebSocketSendable {
    func send<S>(text: S) async where S: Collection, S.Element == Character
    func send(bytes: [UInt8]) async
    func send<Data>(data: Data) async where Data: DataProtocol
    func send<Data>(data: Data, opcode: WebSocketOpcode) async where Data: DataProtocol
    func send<C>(model: C) async throws where C: Encodable
    func send<C>(model: C, encoder: Encoder) async throws where C: Encodable
    func send<T: Codable>(event: EID<T>) async throws
    func send<T: Codable>(event: EID<T>, payload: T?) async throws
    func sendPing() async
}

@WebSocketActor
internal protocol _WebSocketSendable: WebSocketSendable {
    var exchangeMode: ExchangeMode { get }
    var logger: Logger { get }
    var _encoder: Encoder { get }
    var sockets: [WebSocket] { get }
}

extension _WebSocketSendable {
    func _send<S>(text: S) where S: Collection, S.Element == Character {
        if exchangeMode == .binary {
            logger.warning("[⚡️] ❗️📤❗️text will be automatically converted to binary data. Observer is in `binary` mode.")
            _send(bytes: Array(String(text).utf8))
            return
        }
        sockets.forEach {
            logger.debug("[⚡️] 📤 text: \(text)")
            $0.send(text)
        }
    }

    func _send(bytes: [UInt8]) {
        if exchangeMode == .text {
            logger.warning("[⚡️] ❗️📤❗️bytes will be automatically converted to text. Observer is in `binary` mode.")
            guard let text = String(bytes: bytes, encoding: .utf8) else {
                logger.warning("[⚡️] ❗️📤❗️Unable to convert bytes to text. Observer is in `binary` mode.")
                return
            }
            _send(text: text)
            return
        }
        sockets.forEach {
            logger.debug("[⚡️] 📤 bytes: \(bytes.count)")
            $0.send(bytes)
        }
    }

    func _send<Data>(data: Data) where Data: DataProtocol {
        _send(data: data, opcode: .binary)
    }

    func _send<Data>(data: Data, opcode: WebSocketOpcode) where Data: DataProtocol {
        if exchangeMode == .text {
            logger.warning("[⚡️] ❗️📤❗️data will be automatically converted to text. Observer is in `text` mode.")
            guard let text = String(bytes: data, encoding: .utf8) else {
                logger.warning("[⚡️] ❗️📤❗️Unable to convert data to text. Observer is in `text` mode.")
                return
            }
            _send(text: text)
            return
        }
        sockets.forEach {
            logger.debug("[⚡️] 📤 data: \(data.count)")
            $0.send(raw: data, opcode: opcode)
        }
    }

    func _send<C>(model: C) throws where C: Encodable {
        try _send(model: model, encoder: _encoder)
    }

    func _send<C>(model: C, encoder: Encoder) throws where C: Encodable {
        let data = try encoder.encode(model)
        if exchangeMode != .text {
            _send(data: data)
        }
        guard exchangeMode != .binary, let text = String(data: data, encoding: .utf8) else { return }
        _send(text: text)
    }

    func _send<T: Codable>(event: EID<T>) throws {
        try _send(event: event, payload: Optional<T>.none)
    }

    func _send<T: Codable>(event: EID<T>, payload: T?) throws {
        try _send(model: Event(event: event.id, payload: payload))
    }

    func _sendPing() {
        sockets.forEach { $0.sendPing() }
    }
}
