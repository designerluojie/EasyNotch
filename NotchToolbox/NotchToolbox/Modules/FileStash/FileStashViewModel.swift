import Combine
import Foundation

enum FileStashExpandedPhase: Equatable {
    case expandedEmpty
    case expandedFilled
    case dragHoverImport
}

struct FileStashCardViewState: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var typeLabel: String
    var itemKind: FileStashItemKind
    var status: FileStashItemStatus
    var resolvedURL: URL?
}

@MainActor
final class FileStashViewModel: ObservableObject {
    @Published private(set) var cards: [FileStashCardViewState] = []
    @Published private(set) var phase: FileStashExpandedPhase = .expandedEmpty
    @Published private(set) var lastImportError: String?

    private let core: FileStashCore
    private var isDropTargeted = false
    private var cancellables: Set<AnyCancellable> = []

    init(core: FileStashCore) {
        self.core = core
        core.$items
            .sink { [weak self] items in
                self?.apply(items: items)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        core.refresh()
    }

    func setDropTargeted(_ isTargeted: Bool) {
        isDropTargeted = isTargeted
        updatePhase()
    }

    func addDroppedFileURLs(_ urls: [URL]) {
        guard urls.isEmpty == false else {
            return
        }

        do {
            try core.stash(urls: urls)
            lastImportError = nil
        } catch {
            lastImportError = "文件暂存失败，请重试。"
        }
        isDropTargeted = false
        updatePhase()
    }

    func delete(cardID: UUID) {
        do {
            try core.delete(id: cardID)
            lastImportError = nil
        } catch {
            lastImportError = "删除暂存文件失败，请重试。"
        }
    }

    private func apply(items: [FileStashItem]) {
        cards = items.map { item in
            FileStashCardViewState(
                id: item.id,
                displayName: item.displayName,
                typeLabel: item.typeLabel,
                itemKind: item.itemKind,
                status: item.status,
                resolvedURL: item.resolvedURL
            )
        }
        updatePhase()
    }

    private func updatePhase() {
        if isDropTargeted {
            phase = .dragHoverImport
        } else if cards.isEmpty {
            phase = .expandedEmpty
        } else {
            phase = .expandedFilled
        }
    }
}
