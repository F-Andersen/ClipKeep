import ApplicationServices
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let draft = model.editing {
                EditorView(model: model, draft: draft)
                    .id(draft.id)
            } else {
                MainView(model: model)
            }
        }
    }
}

// MARK: - Головний екран

struct MainView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            if model.autoPaste && !model.accessibilityOK { accessibilityBanner }
            Divider()
            footer
        }
        .onAppear { searchFocused = true }
        .onReceive(model.$openCounter) { _ in
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.tab) {
                Text("Історія").tag(Tab.history)
                Text("Закріплені").tag(Tab.pinned)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Пошук", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    IconButton(symbol: "xmark.circle.fill", help: "Очистити пошук") { model.query = "" }
                }
                if model.tab == .pinned {
                    IconButton(symbol: "plus", help: "Новий запис") { model.startNew() }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
        }
        .padding(10)
    }

    private var list: some View {
        let items = model.visible
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        RowView(model: model, item: item, index: index, selected: index == model.selection)
                            .id(item.id)
                    }
                }
                .padding(6)
            }
            .overlay {
                if items.isEmpty { emptyState }
            }
            .onChange(of: model.selection) { _, new in
                let v = model.visible
                if v.indices.contains(new) { proxy.scrollTo(v[new].id) }
            }
            .onChange(of: model.tab) { _, _ in
                if let first = model.visible.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: model.tab == .history ? "doc.on.clipboard" : "pin")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(emptyText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    private var emptyText: String {
        if !model.query.isEmpty { return "Нічого не знайдено" }
        return model.tab == .history
            ? "Скопіюйте будь-який текст —\nвін з’явиться тут"
            : "Тут зберігаються постійні записи.\nНатисніть «+» або закріпіть запис з історії."
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Для автовставки потрібен дозвіл «Універсальний доступ». Якщо NotchClip уже є в списку — видаліть його «−» і додайте знову.")
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Дозволити") { model.requestAccessibility() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        // щойно дозвіл з'явиться — смужка зникне сама
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if AXIsProcessTrusted() { model.accessibilityOK = true }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(countText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if model.tab == .history && !model.history.isEmpty {
                Button("Очистити історію") { model.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Menu {
                Toggle("Автовставка в активне вікно", isOn: $model.autoPaste)
                Toggle("Запускати при вході в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle("Іконка в меню-барі", isOn: $model.showMenuBarIcon)
                Picker("Розмір історії", selection: $model.historyLimit) {
                    ForEach([20, 50, 100, 200], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)
                Divider()
                Text("Відкрити: клік по вирізу камери або ⇧⌘V")
                Text("Вставити: клік, ↩ або ⌘1…⌘9")
                Text("⌥↩ — лише скопіювати · ⇥ — вкладки")
                Divider()
                Button("Вийти з NotchClip") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var countText: String {
        if model.tab == .history { return "\(model.history.count) з \(model.historyLimit)" }
        let n = model.pinned.count
        return "\(n) \(ukPlural(n, "запис", "записи", "записів"))"
    }
}

// MARK: - Рядок

struct RowView: View {
    @ObservedObject var model: AppModel
    let item: ClipItem
    let index: Int
    let selected: Bool
    @State private var hover = false

    private var inPinnedTab: Bool { model.tab == .pinned }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                Text(item.preview)
                    .font(.system(size: 12))
                    .lineLimit(item.title.isEmpty ? 2 : 1)
                    .foregroundStyle(item.title.isEmpty ? Color.primary : Color.secondary)
            }
            Spacer(minLength: 4)
            if hover {
                HStack(spacing: 0) { actionButtons }
            } else {
                if !inPinnedTab && model.isPinned(item) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.22)
                      : hover ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.pick(item) }
        .contextMenu { contextItems }
        .help(String(item.text.prefix(600)))
    }

    @ViewBuilder private var actionButtons: some View {
        if inPinnedTab {
            IconButton(symbol: "pencil", help: "Редагувати") { model.startEdit(item) }
        } else {
            let pinned = model.isPinned(item)
            IconButton(symbol: pinned ? "pin.slash" : "pin", help: pinned ? "Відкріпити" : "Закріпити") {
                model.togglePin(item)
            }
        }
        IconButton(symbol: "trash", help: "Видалити") { model.delete(item) }
    }

    @ViewBuilder private var contextItems: some View {
        Button("Вставити") { model.pick(item) }
        Button("Лише скопіювати") { model.pick(item, paste: false) }
        Divider()
        if inPinnedTab {
            Button("Редагувати…") { model.startEdit(item) }
            Button("Перемістити вгору") { model.movePinned(item, by: -1) }
            Button("Перемістити вниз") { model.movePinned(item, by: 1) }
        } else {
            Button(model.isPinned(item) ? "Відкріпити" : "Закріпити") { model.togglePin(item) }
        }
        Divider()
        Button("Видалити") { model.delete(item) }
    }
}

// MARK: - Редактор закріпленого запису

struct EditorView: View {
    @ObservedObject var model: AppModel
    @State private var draft: ClipItem
    @FocusState private var focus: Field?
    private enum Field { case title, text }

    init(model: AppModel, draft: ClipItem) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { !model.pinned.contains { $0.id == draft.id } }
    private var canSave: Bool { !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "Новий постійний запис" : "Редагування запису")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Назва (необов’язково)").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("напр. Email, Адреса, Підпис", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .title)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Текст").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $draft.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                    .focused($focus, equals: .text)
            }

            HStack {
                Text("⌘↩ — зберегти").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Button("Скасувати") { model.editing = nil }
                Button("Зберегти") { model.savePinned(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(14)
        .onAppear {
            DispatchQueue.main.async { focus = draft.text.isEmpty ? .text : .title }
        }
    }
}

// MARK: - Дрібниці

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}
