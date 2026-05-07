import Foundation
import Combine

@MainActor
final class OverlayPanelInteractions: ObservableObject {
    private let hotzoneController: HotzoneController

    var requestExpand: ((String) -> Void)?
    var requestCollapse: ((String) -> Void)?
    var requestPointerEnter: ((String) -> Void)?
    var requestPointerExit: ((String) -> Void)?
    var requestCollapseTimeout: ((String) -> Void)?

    init(hotzoneController: HotzoneController? = nil) {
        self.hotzoneController = hotzoneController ?? HotzoneController()
        self.hotzoneController.requestPointerEnter = { [weak self] screenID in
            let requestPointerEnter = self?.requestPointerEnter
            Task { @MainActor in
                requestPointerEnter?(screenID)
            }
        }
        self.hotzoneController.requestPointerExit = { [weak self] screenID in
            let requestPointerExit = self?.requestPointerExit
            Task { @MainActor in
                requestPointerExit?(screenID)
            }
        }
        self.hotzoneController.requestCollapseTimeout = { [weak self] screenID in
            let requestCollapseTimeout = self?.requestCollapseTimeout
            Task { @MainActor in
                requestCollapseTimeout?(screenID)
            }
        }
    }

    func expand(screenID: String) {
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        let requestExpand = requestExpand
        Task { @MainActor in
            requestExpand?(screenID)
        }
    }

    func collapse(screenID: String) {
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        let requestCollapse = requestCollapse
        Task { @MainActor in
            requestCollapse?(screenID)
        }
    }

    func pointerEntered(screenID: String) {
        hotzoneController.pointerEntered(screenID: screenID)
    }

    func pointerExited(screenID: String) {
        hotzoneController.pointerExited(screenID: screenID)
    }
}
