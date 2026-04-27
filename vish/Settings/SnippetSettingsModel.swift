import Foundation

@MainActor
final class SnippetSettingsModel: ObservableObject {
    @Published private(set) var items: [SnippetRecord] = []
    @Published var selectedID: String?
    @Published var trigger = ";"
    @Published var expansion = ""

    var canSave: Bool {
        SnippetRecord.normalizedTrigger(trigger) != nil
            && SnippetRecord.cleanedExpansion(expansion) != nil
    }

    func load() {
        Task {
            let loaded = await SnippetStore.shared.list()
            items = loaded
            if let selectedID, let selected = loaded.first(where: { $0.id == selectedID }) {
                select(selected)
            } else if selectedID == nil, let first = loaded.first {
                select(first)
            }
        }
    }

    func select(_ item: SnippetRecord) {
        selectedID = item.id
        trigger = item.trigger
        expansion = item.expansion
    }

    func new() {
        selectedID = nil
        trigger = ";"
        expansion = ""
    }

    func useStarter(_ starter: SnippetStarter) {
        selectedID = nil
        trigger = starter.trigger
        expansion = starter.expansion
    }

    func insertToken(_ token: SnippetToken) {
        let separator = expansion.isEmpty || expansion.hasSuffix(" ") || expansion.hasSuffix("\n") ? "" : " "
        expansion += separator + token.value
    }

    func save() {
        let id = selectedID
        let trigger = trigger
        let expansion = expansion
        Task {
            guard let saved = await SnippetStore.shared.upsert(id: id, trigger: trigger, expansion: expansion) else { return }
            items = await SnippetStore.shared.list()
            if let selected = items.first(where: { $0.id == saved.id }) {
                select(selected)
            }
        }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        Task {
            await SnippetStore.shared.delete(id: id)
            items = await SnippetStore.shared.list()
            if let first = items.first {
                select(first)
            } else {
                new()
            }
        }
    }
}
