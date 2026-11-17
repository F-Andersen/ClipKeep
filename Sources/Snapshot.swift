import AppKit
import SwiftUI

/// Службовий режим `NotchClip --snapshot <папка>`: рендерить справжній інтерфейс
/// з демо-даними на макеті робочого столу (для README і перевірки вигляду).
enum Snapshot {
    static let sceneWidth: CGFloat = 1000
    static let notch = CGSize(width: 185, height: 32)

    static func run(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = demoModel()
        let state = NotchState()
        state.notchSize = notch
        state.notchMidX = 0
        state.windowMidX = 0

        // Згорнутий стан у трьох варіантах вільного місця
        state.earLeft = 30; state.earRight = 30
        render(state, model, .sparse, height: 72, "\(dir)/collapsed.png")
        state.earRight = 0
        render(state, model, .crowdedRight, height: 72, "\(dir)/collapsed-left.png")
        state.earLeft = 0
        render(state, model, .crowded, height: 72, "\(dir)/collapsed-hidden.png")

        // «Скопійовано»
        state.earLeft = 30; state.earRight = 30
        state.flashing = true
        render(state, model, .sparse, height: 90, "\(dir)/copied.png")
        state.flashing = false

        // Відкрита панель
        state.expanded = true
        model.tab = .history
        model.selection = 1
        render(state, model, .sparse, height: 560, "\(dir)/panel-history.png")

        model.tab = .pinned
        model.selection = 0
        render(state, model, .sparse, height: 560, "\(dir)/panel-pinned.png")

        model.editing = model.pinned[2]
        render(state, model, .sparse, height: 560, "\(dir)/panel-editor.png")
        model.editing = nil

        model.tab = .history
        model.accessibilityOK = false
        render(state, model, .sparse, height: 560, "\(dir)/panel-permission.png")
    }

    private static func demoModel() -> AppModel {
        let model = AppModel(persist: false)
        model.accessibilityOK = true
        model.history = [
            "https://example.com/docs/getting-started",
            "Дякую, отримав! Подивлюсь сьогодні ввечері і відпишу.",
            "git commit -m \"fix: clipboard history\"",
            "func greet(name: String) {\n    print(\"Hello, \\(name)\")\n}",
            "+380 00 000 00 00",
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore",
            "name@example.com",
        ].map { ClipItem(text: $0) }
        model.pinned = [
            ClipItem(title: "Email", text: "name@example.com"),
            ClipItem(title: "Адреса", text: "м. Київ, вул. Прикладна, 1, кв. 2"),
            ClipItem(title: "Підпис", text: "З повагою,\nІм’я Прізвище"),
            ClipItem(title: "Реквізити", text: "UA00 0000 0000 0000 0000 0000 000"),
            ClipItem(text: "Добрий день! Дякую за звернення, відповім найближчим часом."),
        ]
        return model
    }

    private static func render(_ state: NotchState, _ model: AppModel, _ bar: FakeMenuBar.Style,
                               height: CGFloat, _ path: String) {
        let scene = ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.33),
                                    Color(red: 0.42, green: 0.30, blue: 0.47),
                                    Color(red: 0.86, green: 0.56, blue: 0.46)],
                           startPoint: .top, endPoint: .bottom)
            FakeMenuBar(style: bar, notch: notch, width: sceneWidth)
            // апаратний виріз
            NotchShape(topLeft: 0, topRight: 0, bottom: 9)
                .fill(Color.black)
                .frame(width: notch.width, height: notch.height)
            NotchView(state: state, model: model, onTap: {}, onBackgroundTap: {})
        }
        .frame(width: sceneWidth, height: height)

        let host = NSHostingView(rootView: scene)
        let rect = NSRect(x: 0, y: 0, width: sceneWidth, height: height)
        host.frame = rect
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Макет меню-бару macOS для знімків.
struct FakeMenuBar: View {
    enum Style { case sparse, crowdedRight, crowded }
    let style: Style
    let notch: CGSize
    let width: CGFloat

    private var leftMenus: [String] {
        style == .crowded
            ? ["Chrome", "Файл", "Правка", "Вигляд", "Історія", "Закладки", "Профілі", "Вкладка", "Вікно"]
            : ["Finder", "Файл", "Правка", "Вигляд"]
    }

    private var icons: [String] {
        let base = ["wifi", "battery.75percent", "magnifyingglass", "switch.2"]
        return style == .sparse
            ? base
            : ["paperplane", "cube", "shippingbox", "lock.shield", "bolt.horizontal", "cloud",
               "globe", "music.note", "camera", "bell"] + base
    }

    var body: some View {
        let half = (width - notch.width) / 2
        HStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 14, weight: .semibold))
                ForEach(Array(leftMenus.enumerated()), id: \.offset) { i, title in
                    Text(title).fontWeight(i == 0 ? .bold : .regular).fixedSize()
                }
            }
            .padding(.leading, 18)
            .frame(width: half, alignment: .leading)
            .clipped()

            Color.clear.frame(width: notch.width)

            HStack(spacing: 15) {
                if style == .crowded { Text("Довідка").fixedSize() }
                ForEach(icons, id: \.self) { Image(systemName: $0) }
                Text("Пн 16 лист. 14:05").fixedSize()
            }
            .padding(.leading, style == .sparse ? 0 : 10)
            .padding(.trailing, 16)
            .frame(width: half, alignment: style == .sparse ? .trailing : .leading)
            .clipped()
        }
        .font(.system(size: 13.5))
        .foregroundStyle(.white)
        .frame(width: width, height: notch.height)
        .background(Color.black.opacity(0.22))
    }
}
