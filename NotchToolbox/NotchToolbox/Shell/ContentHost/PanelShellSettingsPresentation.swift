import CoreGraphics

@MainActor
struct PanelShellSettingsPresentation {
    weak var presenter: (any SettingsPresenting)?

    func showSettings(centeredOn screenFrame: CGRect?) {
        presenter?.show(centeredOn: screenFrame)
    }
}
