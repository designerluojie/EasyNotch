import Foundation

nonisolated enum ResolvedRestPresentation: Equatable, Sendable {
    case none
    case request(RestVariantRequest)

    var isTransientRequest: Bool {
        guard case .request(let request) = self,
              case .transient = request.lifetime else {
            return false
        }

        return true
    }
}
