import Foundation

nonisolated enum RestVariantLifetime: Equatable, Sendable {
    case persistent
    case transient(token: UUID, duration: Duration, declaredAt: Date)
}
