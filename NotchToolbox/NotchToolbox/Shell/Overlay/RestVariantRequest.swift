import CoreGraphics
import Foundation

nonisolated struct RestVariantRequest: Equatable, Sendable {
    let moduleID: NotchModuleID
    let kind: RestVariantKind
    let preferredWidth: CGFloat?
    let preferredHeight: CGFloat?
    let lifetime: RestVariantLifetime

    init(
        moduleID: NotchModuleID,
        kind: RestVariantKind,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        lifetime: RestVariantLifetime = .persistent
    ) {
        self.moduleID = moduleID
        self.kind = kind
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.lifetime = lifetime
    }
}
