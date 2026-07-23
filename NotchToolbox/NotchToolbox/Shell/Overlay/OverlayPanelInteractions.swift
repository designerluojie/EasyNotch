import Foundation
import Combine
import CoreGraphics
import AppKit

@MainActor
final class OverlayPanelInteractions: ObservableObject {
    private let hotzoneController: HotzoneController
    private var isFileStashInternalDragActive = false
    private var isCurrentFileDropSessionFromFileStash = false
    private var internalDragResetTask: Task<Void, Never>?
    private var internalDragMouseButtonPollingTask: Task<Void, Never>?
    private var localInternalDragEndMonitor: Any?
    private var globalInternalDragEndMonitor: Any?
    private var isExpandRequestPending = false

    var requestExpand: ((String) -> Void)?
    var requestExpandModule: ((String, NotchModuleID) -> Void)?
    var requestCollapse: ((String) -> Void)?
    var requestPointerEnter: ((String) -> Void)?
    var requestPointerExit: ((String) -> Void)?
    var requestCollapseTimeout: ((String) -> Void)?
    var requestFileDragEnter: ((String) -> Void)?
    var requestFileDragExit: ((String) -> Void)?
    var requestFileDrop: ((String, [URL], CGPoint) -> Void)?

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
        guard isExpandRequestPending == false else {
            return
        }

        isExpandRequestPending = true
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.isExpandRequestPending = false
            let requestExpand = self.requestExpand
            requestExpand?(screenID)
        }
    }

    func expand(screenID: String, moduleID: NotchModuleID) {
        guard isExpandRequestPending == false else {
            return
        }

        isExpandRequestPending = true
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.isExpandRequestPending = false
            let requestExpandModule = self.requestExpandModule
            requestExpandModule?(screenID, moduleID)
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

    func fileDragEntered(screenID: String) {
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        if isFileStashInternalDragActive {
            isCurrentFileDropSessionFromFileStash = true
            return
        }

        let requestFileDragEnter = requestFileDragEnter
        Task { @MainActor in
            requestFileDragEnter?(screenID)
        }
    }

    func fileDragExited(screenID: String) {
        guard !isCurrentFileDropSessionFromFileStash else {
            clearFileStashInternalDrag()
            return
        }

        let requestFileDragExit = requestFileDragExit
        Task { @MainActor in
            requestFileDragExit?(screenID)
        }
    }

    func fileDropped(screenID: String, urls: [URL], location: CGPoint) {
        hotzoneController.cancelCollapseTimeout(screenID: screenID)
        guard !isCurrentFileDropSessionFromFileStash else {
            clearFileStashInternalDrag()
            return
        }

        let requestFileDrop = requestFileDrop
        Task { @MainActor in
            requestFileDrop?(screenID, urls, location)
        }
    }

    func fileStashInternalDragStarted() {
        isFileStashInternalDragActive = true
        isCurrentFileDropSessionFromFileStash = false
        installInternalDragEndMonitors()
        startInternalDragMouseButtonPolling()
        internalDragResetTask?.cancel()
        internalDragResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                self?.clearFileStashInternalDrag()
            }
        }
    }

    func fileStashInternalDragEnded() {
        isFileStashInternalDragActive = false
        internalDragResetTask?.cancel()
        internalDragResetTask = nil
        removeInternalDragEndMonitors()
        stopInternalDragMouseButtonPolling()
    }

    func fileStashInternalDragMouseButtonsChanged(pressedMouseButtons: Int) {
        guard isFileStashInternalDragActive else {
            return
        }

        let leftMouseButtonMask = 1
        if pressedMouseButtons & leftMouseButtonMask == 0 {
            clearFileStashInternalDrag()
        }
    }

    private func clearFileStashInternalDrag() {
        isFileStashInternalDragActive = false
        isCurrentFileDropSessionFromFileStash = false
        internalDragResetTask?.cancel()
        internalDragResetTask = nil
        removeInternalDragEndMonitors()
        stopInternalDragMouseButtonPolling()
    }

    private func installInternalDragEndMonitors() {
        guard localInternalDragEndMonitor == nil, globalInternalDragEndMonitor == nil else {
            return
        }

        localInternalDragEndMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.fileStashInternalDragEnded()
            return event
        }

        globalInternalDragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.fileStashInternalDragEnded()
            }
        }
    }

    private func removeInternalDragEndMonitors() {
        if let localInternalDragEndMonitor {
            NSEvent.removeMonitor(localInternalDragEndMonitor)
            self.localInternalDragEndMonitor = nil
        }

        if let globalInternalDragEndMonitor {
            NSEvent.removeMonitor(globalInternalDragEndMonitor)
            self.globalInternalDragEndMonitor = nil
        }
    }

    private func startInternalDragMouseButtonPolling() {
        internalDragMouseButtonPollingTask?.cancel()
        internalDragMouseButtonPollingTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else {
                    return
                }
                await MainActor.run {
                    self.fileStashInternalDragMouseButtonsChanged(
                        pressedMouseButtons: NSEvent.pressedMouseButtons
                    )
                }
            }
        }
    }

    private func stopInternalDragMouseButtonPolling() {
        internalDragMouseButtonPollingTask?.cancel()
        internalDragMouseButtonPollingTask = nil
    }
}
