import Foundation
import Vapor

public protocol Encoder: Swift.Sendable {
    func encode<T>(_ value: T) throws -> Data where T : Encodable
}

extension JSONEncoder: Encoder {}
