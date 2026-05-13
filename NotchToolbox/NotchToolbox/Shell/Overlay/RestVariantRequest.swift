import Foundation

nonisolated struct RestVariantRequest: Equatable, Sendable {
    let moduleID: NotchModuleID
    let kind: RestVariantKind
}
