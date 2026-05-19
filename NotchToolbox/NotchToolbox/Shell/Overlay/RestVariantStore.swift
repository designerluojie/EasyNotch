import Foundation

@MainActor
final class RestVariantStore {
    private var persistentRequests: [NotchModuleID: RestVariantRequest] = [:]
    private var activeTransientRequest: RestVariantRequest?
    private var queuedTransientRequests: [RestVariantRequest] = []
    private let transientBridgeDelay: Duration
    private var activeTransientTask: Task<Void, Never>?
    private var transientBridgeTask: Task<Void, Never>?

    var onResolvedPresentationChange: ((ResolvedRestPresentation) -> Void)?

    init(transientBridgeDelay: Duration = .milliseconds(200)) {
        self.transientBridgeDelay = transientBridgeDelay
    }

    var resolvedPresentation: ResolvedRestPresentation {
        if let activeTransientRequest {
            return .request(activeTransientRequest)
        }

        if let request = persistentRequests.values.sorted(by: { $0.moduleID.rawValue < $1.moduleID.rawValue }).first {
            return .request(request)
        }

        return .none
    }

    func setPersistentRequest(_ request: RestVariantRequest) {
        persistentRequests[request.moduleID] = RestVariantRequest(
            moduleID: request.moduleID,
            kind: request.kind,
            preferredWidth: request.preferredWidth,
            preferredHeight: request.preferredHeight
        )
        publishResolvedPresentationIfNeeded()
    }

    func clearPersistentRequest(for moduleID: NotchModuleID) {
        persistentRequests[moduleID] = nil
        publishResolvedPresentationIfNeeded()
    }

    func enqueueTransientRequest(_ request: RestVariantRequest) {
        guard case .transient = request.lifetime else {
            setPersistentRequest(request)
            return
        }

        queuedTransientRequests.append(request)
        queuedTransientRequests.sort(by: Self.transientRequestComesFirst(_:_:))
        activateNextTransientIfPossible()
    }

    deinit {
        activeTransientTask?.cancel()
        transientBridgeTask?.cancel()
    }

    private func activateNextTransientIfPossible() {
        guard activeTransientRequest == nil, transientBridgeTask == nil else {
            return
        }

        guard let nextRequest = queuedTransientRequests.first else {
            return
        }

        queuedTransientRequests.removeFirst()
        activeTransientRequest = nextRequest
        publishResolvedPresentationIfNeeded()
        scheduleTransientExpiry(for: nextRequest)
    }

    private func scheduleTransientExpiry(for request: RestVariantRequest) {
        activeTransientTask?.cancel()
        activeTransientTask = Task { [weak self] in
            guard case .transient(let token, let duration, _) = request.lifetime else {
                return
            }

            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }

            self?.expireTransient(token: token)
        }
    }

    private func expireTransient(token: UUID) {
        guard case .transient(let activeToken, _, _) = activeTransientRequest?.lifetime,
              activeToken == token else {
            return
        }

        activeTransientTask?.cancel()
        activeTransientTask = nil
        activeTransientRequest = nil
        publishResolvedPresentationIfNeeded()

        guard queuedTransientRequests.isEmpty == false else {
            return
        }

        transientBridgeTask?.cancel()
        transientBridgeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.transientBridgeDelay ?? .zero)
            } catch {
                return
            }

            self?.finishTransientBridge()
        }
    }

    private func finishTransientBridge() {
        transientBridgeTask?.cancel()
        transientBridgeTask = nil
        activateNextTransientIfPossible()
    }

    private func publishResolvedPresentationIfNeeded() {
        onResolvedPresentationChange?(resolvedPresentation)
    }

    private static func transientRequestComesFirst(
        _ lhs: RestVariantRequest,
        _ rhs: RestVariantRequest
    ) -> Bool {
        switch (lhs.lifetime, rhs.lifetime) {
        case let (.transient(_, _, lhsDate), .transient(_, _, rhsDate)):
            return lhsDate < rhsDate
        default:
            return lhs.moduleID.rawValue < rhs.moduleID.rawValue
        }
    }
}
