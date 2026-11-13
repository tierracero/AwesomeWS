import Foundation
import Vapor
import NIOConcurrencyHelpers

final class _Storage: Swift.Sendable {
    private let state = NIOLockedValueBox<[String: any AnyObserver]>([:])

    var items: [String: any AnyObserver] {
        state.withLockedValue { $0 }
    }

    struct Key: StorageKey {
        typealias Value = _Storage
    }

    private struct InitializationLock: LockKey {}

    subscript(_ member: String) -> (any AnyObserver)? {
        get { state.withLockedValue { $0[member] } }
        set {
            state.withLockedValue { items in
                if let newValue {
                    guard items[member] == nil else { return }
                    items[member] = newValue
                } else {
                    items.removeValue(forKey: member)
                }
            }
        }
    }

    static func get(on application: Application) -> _Storage {
        application.locks.lock(for: InitializationLock.self).withLock {
            if let existing = application.storage[Key.self] { return existing }
            let storage = _Storage()
            application.storage[Key.self] = storage
            return storage
        }
    }
}

extension Application {
    var wsStorage: _Storage { _Storage.get(on: self) }
}
