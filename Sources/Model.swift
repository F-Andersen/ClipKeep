import AppKit
import ApplicationServices
import ServiceManagement

struct ClipItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var text: String
    var date = Date()

    /// Однорядкове прев'ю: без переносів і зайвих пробілів.
    var preview: String {
        text.prefix(400).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

enum Tab: String {
    case history, pinned
}

private struct SavedData: Codable {
    var pinned: [ClipItem]
    var history: [ClipItem]
}

final class AppModel: ObservableObject {
    @Published var pinned: [ClipItem] = []
    @Published var history: [ClipItem] = []

    @Published var tab: Tab = .history { didSet { if oldValue != tab { selection = 0 } } }
    @Published var query = "" { didSet { if oldValue != query { selection = 0 } } }
    @Published var selection = 0
    @Published var editing: ClipItem?
    @Published var openCounter = 0

    @Published var accessibilityOK = AXIsProcessTrusted()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var historyLimit: Int {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
            trimHistory()
            save()
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    /// (запис, чи вставляти в активне вікно) — обробляє AppDelegate.
    var onPick: ((ClipItem, Bool) -> Void)?

    private let persist: Bool
    private let fileURL: URL

    init(persist: Bool = true) {
        self.persist = persist
        autoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        historyLimit = UserDefaults.standard.object(forKey: "historyLimit") as? Int ?? 50
        showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("NotchClip", isDirectory: true)
        fileURL = dir.appendingPathComponent("data.json")
        if persist {
            // перенос даних зі старої назви (ClipKeep), щоб історія і закріплені не загубились
            let legacy = support.appendingPathComponent("ClipKeep", isDirectory: true)
            let fm = FileManager.default
            if !fm.fileExists(atPath: dir.path) && fm.fileExists(atPath: legacy.path) {
                try? fm.moveItem(at: legacy, to: dir)
            }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            load()
        }
    }

    // MARK: - Список, що зараз на екрані

    var visible: [ClipItem] {
        let source = tab == .history ? history : pinned
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return source }
        return source.filter {
            $0.text.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q)
        }
    }

    var selectedItem: ClipItem? {
        let v = visible
        return v.indices.contains(selection) ? v[selection] : nil
    }

    func moveSelection(_ delta: Int) {
        let n = visible.count
        guard n > 0 else { return }
        selection = max(0, min(n - 1, selection + delta))
    }

    /// Скидає пошук/вибір перед кожним відкриттям панелі.
    func prepareForOpen() {
        editing = nil
        query = ""
        selection = 0
        accessibilityOK = AXIsProcessTrusted()
    }

    func pick(_ item: ClipItem, paste: Bool = true) {
        onPick?(item, paste)
    }

    func pick(at index: Int) {
        let v = visible
        if v.indices.contains(index) { pick(v[index]) }
    }

    // MARK: - Історія

    func addFromClipboard(_ text: String) {
        guard text.utf16.count <= 1_000_000 else { return }
        history.removeAll { $0.text == text }
        history.insert(ClipItem(text: text), at: 0)
        trimHistory()
        save()
    }

    /// Піднімає запис історії нагору після використання.
    func bump(_ item: ClipItem) {
        guard let i = history.firstIndex(where: { $0.id == item.id }), i != 0 else { return }
        var it = history.remove(at: i)
        it.date = Date()
        history.insert(it, at: 0)
        save()
    }

    func clearHistory() {
        history.removeAll()
        selection = 0
        save()
    }

    private func trimHistory() {
        if history.count > historyLimit { history.removeLast(history.count - historyLimit) }
    }

    // MARK: - Закріплені

    func isPinned(_ item: ClipItem) -> Bool {
        pinned.contains { $0.text == item.text }
    }

    func togglePin(_ item: ClipItem) {
        if let i = pinned.firstIndex(where: { $0.text == item.text }) {
            pinned.remove(at: i)
        } else {
            pinned.append(ClipItem(text: item.text))
        }
        save()
    }

    func movePinned(_ item: ClipItem, by delta: Int) {
        guard let i = pinned.firstIndex(where: { $0.id == item.id }) else { return }
        let j = i + delta
        guard pinned.indices.contains(j) else { return }
        pinned.swapAt(i, j)
        if tab == .pinned && query.isEmpty { selection = j }
        save()
    }

    func startNew() { editing = ClipItem(text: "") }
    func startEdit(_ item: ClipItem) { editing = item }

    func savePinned(_ draft: ClipItem) {
        var d = draft
        d.title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = pinned.firstIndex(where: { $0.id == d.id }) {
            pinned[i] = d
        } else {
            pinned.append(d)
            tab = .pinned
        }
        editing = nil
        save()
    }

    func delete(_ item: ClipItem) {
        pinned.removeAll { $0.id == item.id }
        history.removeAll { $0.id == item.id }
        selection = min(selection, max(0, visible.count - 1))
        save()
    }

    // MARK: - Налаштування

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("NotchClip: launch at login error: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityOK = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !accessibilityOK,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Збереження

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SavedData.self, from: data) else { return }
        pinned = saved.pinned
        history = saved.history
        trimHistory()
    }

    func save() {
        guard persist else { return }
        guard let data = try? JSONEncoder().encode(SavedData(pinned: pinned, history: history)) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // історія буфера може містити приватне — лише для власника
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

func ukPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n10 = n % 10, n100 = n % 100
    if n10 == 1 && n100 != 11 { return one }
    if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
    return many
}
