import Foundation

@MainActor
final class RestVariantStore {
    private var persistentRequests: [NotchModuleID: RestVariantRequest] = [:]

    var resolvedPresentation: ResolvedRestPresentation {
        if let request = persistentRequests.values.sorted(by: { $0.moduleID.rawValue < $1.moduleID.rawValue }).first {
            return .request(request)
        }

        return .none
    }

    func setPersistentRequest(_ request: RestVariantRequest) {
        persistentRequests[request.moduleID] = request
    }

    func clearPersistentRequest(for moduleID: NotchModuleID) {
        persistentRequests[moduleID] = nil
    }
}
