import Combine
import Foundation

enum ClipboardExpandedPhase: Equatable {
    case history
    case pastebackSuccess
}

@MainActor
final class ClipboardViewModel: ObservableObject {
    typealias DelayScheduler = @MainActor (Duration, @escaping @MainActor () -> Void) -> Task<Void, Never>

    @Published private(set) var cards: [ClipboardCardViewState] = []
    @Published private(set) var isEmpty = true
    @Published private(set) var lastPasteError: String?
    @Published private(set) var phase: ClipboardExpandedPhase = .history

    private static let missingItemErrorMessage = "该候选内容已不可用，请重新复制后再试。"
    private static let genericPasteErrorMessage = "放回剪贴板失败，请重试。"

    private let core: ClipboardCore
    private let thumbnailsDirectoryURL: URL?
    private let referenceValidator: ClipboardReferenceValidator
    private let successPhaseDuration: Duration
    private let postCollapseResetDelay: Duration
    private let delayScheduler: DelayScheduler
    private var cancellables: Set<AnyCancellable> = []
    private var pendingSuccessCollapseTask: Task<Void, Never>?
    private var pendingSuccessResetTask: Task<Void, Never>?

    init(
        core: ClipboardCore,
        localFileStore: LocalFileStore? = nil,
        referenceValidator: ClipboardReferenceValidator? = nil,
        restVariantStore: RestVariantStore? = nil,
        successPhaseDuration: Duration = .seconds(2),
        postCollapseResetDelay: Duration = .milliseconds(250),
        delayScheduler: DelayScheduler? = nil
    ) {
        self.core = core
        self.thumbnailsDirectoryURL = localFileStore?.url(for: .clipboardThumbnails)
        self.referenceValidator = referenceValidator ?? ClipboardReferenceValidator()
        _ = restVariantStore
        self.successPhaseDuration = successPhaseDuration
        self.postCollapseResetDelay = postCollapseResetDelay
        self.delayScheduler = delayScheduler ?? Self.defaultDelayScheduler
        core.$history
            .sink { [weak self] history in
                self?.apply(history: history)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        apply(history: core.history)
    }

    func paste(itemID: UUID, onSuccess: (() -> Void)? = nil) {
        guard let item = core.history.first(where: { $0.id == itemID }) else {
            lastPasteError = Self.missingItemErrorMessage
            return
        }

        do {
            try core.paste(item: item)
            lastPasteError = nil
            beginPastebackSuccessPhase(onCollapseRequested: onSuccess)
        } catch {
            lastPasteError = Self.makePasteErrorMessage(from: error)
        }
    }

    private func apply(history: [ClipboardHistoryItem]) {
        cards = history.map(makeCard)
        isEmpty = history.isEmpty
    }

    private func makeCard(_ item: ClipboardHistoryItem) -> ClipboardCardViewState {
        let isMissingReference = hasMissingReference(item)
        let thumbnail = makeThumbnail(from: item.thumbnail)
        let previewState: ClipboardCardPreviewState

        if isMissingReference {
            if let thumbnail {
                previewState = .thumbnailWithMissingReference(thumbnail)
            } else {
                previewState = .missingReferencePlaceholder
            }
        } else if let thumbnail {
            previewState = .thumbnail(thumbnail)
        } else {
            previewState = .textOnly
        }

        return ClipboardCardViewState(
            id: item.id,
            sourceTitle: item.sourceAppName ?? "Unknown",
            sourceAppBundleID: item.sourceAppBundleID,
            sourceAppName: item.sourceAppName,
            relativeTimeText: Self.relativeTimeText(for: item.copiedAt, relativeTo: Date()),
            previewText: item.previewText,
            previewState: previewState,
            contentType: item.contentType,
            isPastebackSupported: true
        )
    }

    private func hasMissingReference(_ item: ClipboardHistoryItem) -> Bool {
        guard case let .fileReferences(references) = item.payload else {
            return false
        }

        do {
            _ = try referenceValidator.validate(references)
            return false
        } catch {
            return true
        }
    }

    private func makeThumbnail(
        from descriptor: ClipboardThumbnailDescriptor?
    ) -> ClipboardCardThumbnail? {
        guard
            let descriptor,
            let thumbnailsDirectoryURL
        else {
            return nil
        }

        let url = thumbnailsDirectoryURL.appending(path: descriptor.fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        return ClipboardCardThumbnail(
            url: url,
            kind: descriptor.kind,
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight
        )
    }

    private static func makePasteErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileNoSuchFileError {
            return "原文件已不存在，无法重新放回剪贴板。"
        }
        return genericPasteErrorMessage
    }

    static func relativeTimeText(for date: Date, relativeTo now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minute = 60.0
        let hour = 60.0 * minute
        let day = 24.0 * hour
        let week = 7.0 * day
        let month = 30.0 * day

        if seconds < minute {
            return "现在"
        }

        if seconds < 11 * minute {
            let minutes = Int(seconds / minute)
            return "\(minutes) 分钟前"
        }

        if seconds < 30 * minute {
            return "15 分钟前"
        }

        if seconds < hour {
            return "半小时前"
        }

        if seconds < 12 * hour {
            let hours = Int(seconds / hour)
            return "\(hours) 小时前"
        }

        if seconds < day {
            return "半天前"
        }

        if seconds < week {
            let days = Int(seconds / day)
            return "\(days) 天前"
        }

        if seconds < 2 * week {
            return "一周前"
        }

        if seconds < 3 * week {
            return "两周前"
        }

        if seconds < 4 * week {
            return "三周前"
        }

        if seconds < 2 * month {
            return "一个月前"
        }

        if seconds < 3 * month {
            return "两个月前"
        }

        if seconds < 4 * month {
            return "三个月前"
        }

        if seconds < 5 * month {
            return "四个月前"
        }

        if seconds < 6 * month {
            return "五个月前"
        }

        if seconds < 12 * month {
            return "半年前"
        }

        if seconds < 24 * month {
            return "一年前"
        }

        return "更久"
    }

    private func beginPastebackSuccessPhase(onCollapseRequested: (() -> Void)?) {
        pendingSuccessCollapseTask?.cancel()
        pendingSuccessResetTask?.cancel()
        phase = .pastebackSuccess

        pendingSuccessCollapseTask = delayScheduler(successPhaseDuration) { [weak self] in
            onCollapseRequested?()
            self?.scheduleHistoryPhaseReset()
        }
    }

    private func scheduleHistoryPhaseReset() {
        pendingSuccessResetTask?.cancel()
        pendingSuccessResetTask = delayScheduler(postCollapseResetDelay) { [weak self] in
            self?.phase = .history
        }
    }

    private static func defaultDelayScheduler(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard Task.isCancelled == false else {
                return
            }

            action()
        }
    }

    deinit {
        pendingSuccessCollapseTask?.cancel()
        pendingSuccessResetTask?.cancel()
    }
}
