import Foundation

nonisolated struct RestVariantRequest: Equatable, Sendable {
    let moduleID: NotchModuleID
    let kind: RestVariantKind
    let lifetime: RestVariantLifetime

    init(
        moduleID: NotchModuleID,
        kind: RestVariantKind,
        lifetime: RestVariantLifetime = .persistent
    ) {
        self.moduleID = moduleID
        self.kind = kind
        self.lifetime = lifetime
    }
}
