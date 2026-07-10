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
    /// Bumped every time a paste error is reported, even when the message is
    /// identical to the previous one, so the view can fire a toast reliably on
    /// repeated failures.
    @Published private(set) var pasteErrorToken: Int = 0
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
        successPhaseDuration: Duration = .seconds(2),
        postCollapseResetDelay: Duration = .milliseconds(250),
        delayScheduler: DelayScheduler? = nil
    ) {
        self.core = core
        self.thumbnailsDirectoryURL = localFileStore?.url(for: .clipboardThumbnails)
        self.referenceValidator = referenceValidator ?? ClipboardReferenceValidator()
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
            reportPasteError(Self.missingItemErrorMessage)
            return
        }

        do {
            try core.paste(item: item)
            lastPasteError = nil
            beginPastebackSuccessPhase(onCollapseRequested: onSuccess)
        } catch {
            reportPasteError(Self.makePasteErrorMessage(from: error))
        }
    }

    private func reportPasteError(_ message: String) {
        lastPasteError = message
        pasteErrorToken += 1
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

    // Deliberately coarse buckets: cards show a vague age, not a precise
    // timestamp (e.g. anything from 11 to 30 minutes reads as "15 分钟前").
    static func relativeTimeText(for date: Date, relativeTo now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minute = 60.0
        let hour = 60.0 * minute
        let day = 24.0 * hour
        let week = 7.0 * day
        let month = 30.0 * day

        let buckets: [(upperBound: Double, text: (Double) -> String)] = [
            (minute, { _ in "现在" }),
            (11 * minute, { "\(Int($0 / minute)) 分钟前" }),
            (30 * minute, { _ in "15 分钟前" }),
            (hour, { _ in "半小时前" }),
            (12 * hour, { "\(Int($0 / hour)) 小时前" }),
            (day, { _ in "半天前" }),
            (week, { "\(Int($0 / day)) 天前" }),
            (2 * week, { _ in "一周前" }),
            (3 * week, { _ in "两周前" }),
            (4 * week, { _ in "三周前" }),
            (2 * month, { _ in "一个月前" }),
            (3 * month, { _ in "两个月前" }),
            (4 * month, { _ in "三个月前" }),
            (5 * month, { _ in "四个月前" }),
            (6 * month, { _ in "五个月前" }),
            (12 * month, { _ in "半年前" }),
            (24 * month, { _ in "一年前" }),
        ]

        for bucket in buckets where seconds < bucket.upperBound {
            return bucket.text(seconds)
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
