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

        if let request = persistentRequests.values.sorted(by: Self.persistentRequestComesFirst(_:_:)).first {
            return .request(request)
        }

        return .none
    }

    func setPersistentRequest(_ request: RestVariantRequest) {
        let previousPresentation = resolvedPresentation
        persistentRequests[request.moduleID] = RestVariantRequest(
            moduleID: request.moduleID,
            kind: request.kind,
            preferredWidth: request.preferredWidth,
            preferredHeight: request.preferredHeight,
            isInteractive: request.isInteractive
        )
        publishResolvedPresentationIfNeeded(from: previousPresentation)
    }

    func clearPersistentRequest(for moduleID: NotchModuleID) {
        let previousPresentation = resolvedPresentation
        persistentRequests[moduleID] = nil
        publishResolvedPresentationIfNeeded(from: previousPresentation)
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

    func replacePersistentRequestWithTransient(
        for moduleID: NotchModuleID,
        request: RestVariantRequest
    ) {
        let previousPresentation = resolvedPresentation
        persistentRequests[moduleID] = nil

        guard case .transient = request.lifetime else {
            persistentRequests[request.moduleID] = RestVariantRequest(
                moduleID: request.moduleID,
                kind: request.kind,
                preferredWidth: request.preferredWidth,
                preferredHeight: request.preferredHeight,
                isInteractive: request.isInteractive
            )
            publishResolvedPresentationIfNeeded(from: previousPresentation)
            return
        }

        queuedTransientRequests.append(request)
        queuedTransientRequests.sort(by: Self.transientRequestComesFirst(_:_:))
        activateNextTransientIfPossible(from: previousPresentation)
    }

    deinit {
        activeTransientTask?.cancel()
        transientBridgeTask?.cancel()
    }

    private func activateNextTransientIfPossible(from previousPresentation: ResolvedRestPresentation? = nil) {
        guard activeTransientRequest == nil, transientBridgeTask == nil else {
            return
        }

        guard let nextRequest = queuedTransientRequests.first else {
            return
        }

        let previousPresentation = previousPresentation ?? resolvedPresentation
        queuedTransientRequests.removeFirst()
        activeTransientRequest = nextRequest
        publishResolvedPresentationIfNeeded(from: previousPresentation)
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
        let previousPresentation = resolvedPresentation
        activeTransientRequest = nil
        publishResolvedPresentationIfNeeded(from: previousPresentation)

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

    private func publishResolvedPresentationIfNeeded(from previousPresentation: ResolvedRestPresentation) {
        let currentPresentation = resolvedPresentation
        guard currentPresentation != previousPresentation else {
            return
        }

        onResolvedPresentationChange?(currentPresentation)
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

    private static func persistentRequestComesFirst(
        _ lhs: RestVariantRequest,
        _ rhs: RestVariantRequest
    ) -> Bool {
        let lhsPriority = persistentPriority(for: lhs.moduleID)
        let rhsPriority = persistentPriority(for: rhs.moduleID)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.moduleID.rawValue < rhs.moduleID.rawValue
    }

    private static func persistentPriority(for moduleID: NotchModuleID) -> Int {
        switch moduleID {
        case .pomodoro:
            return 0
        default:
            return 1
        }
    }
}
