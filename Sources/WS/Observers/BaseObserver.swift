import Foundation
import Vapor

@WebSocketActor
open class BaseObserver {
    nonisolated public let key: String
    nonisolated public let path: String
    nonisolated public let logger: Logger
    nonisolated public let application: Application
    nonisolated public let exchangeMode: ExchangeMode
    public var encoder: Encoder?
    public var decoder: Decoder?

    public var clients: [AnyClient] { _clients }
    var _clients: [_AnyClient] = []

    public nonisolated required init (app: Application, key: String, path: String, exchangeMode: ExchangeMode) {
        self.application = app
        self.logger = app.logger
        self.key = key
        self.path = path.count > 0 ? path : "/"
        self.exchangeMode = exchangeMode
    }
    
    private var initialized = false

    func initialize(encoder: (any Encoder)?, decoder: (any Decoder)?) {
        guard !initialized else { return }
        initialized = true
        setup()
        if let encoder { self.encoder = encoder }
        if let decoder { self.decoder = decoder }
    }

    /// Runs once on WebSocketActor before connection callbacks. Builder codecs override setup codecs.
    open func setup() {}
    
    // MARK: see `AnyObserver`
    
    open func on(open client: AnyClient) {}
    open func on(close client: AnyClient) {}
    open func on(ping client: AnyClient) {}
    open func on(pong client: AnyClient) {}
    open func on(text: String, client: AnyClient) {}
    open func on(byteBuffer: ByteBuffer, client: AnyClient) {}
    open func on(data: Data, client: AnyClient) {}
}
