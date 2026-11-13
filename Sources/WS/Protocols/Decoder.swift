import Foundation
import Vapor

public protocol Decoder: Swift.Sendable {
    func decode<T>(_ type: T.Type, from data: Data) throws -> T where T : Decodable
}

extension JSONDecoder: Decoder {}
