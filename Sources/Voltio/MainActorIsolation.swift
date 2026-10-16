import Foundation

/// Containment point for the C-callback/delegate bridges that must hop onto the
/// main actor. CoreBluetooth delegate callbacks and the IOKit power-source
/// callback are both delivered on the main dispatch queue (the main actor's
/// executor), so `assumeIsolated` is sound there — this helper documents that
/// contract in one place instead of scattering the assumption across call sites.
enum MainActorIsolation {
    /// Run `body` on the main actor without an async hop. Only call from
    /// callbacks that are guaranteed to execute on the main thread (main-queue
    /// delivered CoreBluetooth/IOKit callbacks); it traps otherwise.
    @discardableResult
    static func assume<T: Sendable>(_ body: @MainActor () throws -> T) rethrows -> T {
        try MainActor.assumeIsolated(body)
    }

    /// Fire-and-forget variant for bodies that mutate main-actor state and
    /// return nothing — the common shape of the delegate shims.
    static func assume(_ body: @MainActor () -> Void) {
        MainActor.assumeIsolated(body)
    }
}
