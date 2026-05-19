import Foundation

nonisolated enum ResolvedRestPresentation: Equatable, Sendable {
    case none
    case request(RestVariantRequest)
}
