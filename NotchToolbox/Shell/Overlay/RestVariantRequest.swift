import CoreGraphics
import Foundation

nonisolated struct RestVariantRequest: Equatable, Sendable {
    let moduleID: NotchModuleID
    let kind: RestVariantKind
    let preferredWidth: CGFloat?
    let preferredHeight: CGFloat?
    let lifetime: RestVariantLifetime
    /// When false the collapsed chrome renders but does not accept clicks or
    /// hover-to-expand — used by the onboarding welcome so the greeting can't
    /// be expanded. Defaults to true (normal rest-variant behaviour).
    let isInteractive: Bool

    init(
        moduleID: NotchModuleID,
        kind: RestVariantKind,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        lifetime: RestVariantLifetime = .persistent,
        isInteractive: Bool = true
    ) {
        self.moduleID = moduleID
        self.kind = kind
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.lifetime = lifetime
        self.isInteractive = isInteractive
    }
}
