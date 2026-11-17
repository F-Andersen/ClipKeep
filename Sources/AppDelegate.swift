import AppKit
import Carbon
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let monitor = ClipboardMonitor()
    private var notch: NotchController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        notch = NotchController(model: model)
        notch.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "NotchClip")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.$showMenuBarIcon
            .sink { [weak self] visible in self?.statusItem.isVisible = visible }
            .store(in: &cancellables)

        model.onPick = { [weak self] item, paste in self?.handlePick(item, paste: paste) }
        monitor.onText = { [weak self] text in
            self?.model.addFromClipboard(text)
            self?.notch.flash()
        }
        monitor.start()

        // ⇧⌘V — відкрити/закрити панель з будь-якої програми
        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey) { [weak self] in
            self?.notch.toggle()
        }
    }

    // MARK: - Іконка в меню-барі

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            notch.toggle()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let open = NSMenuItem(title: "Відкрити NotchClip", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Вийти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func openFromMenu() { notch.expand() }

    // MARK: - Вибір запису

    private func handlePick(_ item: ClipItem, paste: Bool) {
        monitor.write(item.text)
        model.bump(item)
        notch.collapse()

        guard paste, model.autoPaste else { return }
        guard AXIsProcessTrusted() else {
            model.accessibilityOK = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardMonitor.sendPaste()
        }
    }

    // MARK: - Клавіатура в панелі

    /// true — клавішу оброблено.
    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)

        if model.editing != nil {
            if e.keyCode == UInt16(kVK_Escape) { model.editing = nil; return true }
            return false
        }

        switch Int(e.keyCode) {
        case kVK_DownArrow:
            model.moveSelection(1); return true
        case kVK_UpArrow:
            model.moveSelection(-1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem {
                model.pick(item, paste: !e.modifierFlags.contains(.option))
            }
            return true
        case kVK_Escape:
            if !model.query.isEmpty { model.query = "" } else { notch.collapse() }
            return true
        case kVK_Tab:
            model.tab = model.tab == .history ? .pinned : .history
            return true
        case kVK_Delete where cmd:
            if let item = model.selectedItem { model.delete(item) }
            return true
        case kVK_ANSI_P where cmd:
            if model.tab == .history, let item = model.selectedItem { model.togglePin(item) }
            return true
        default:
            break
        }

        if cmd, let chars = e.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit) {
            model.pick(at: digit - 1)
            return true
        }
        return false
    }

    // MARK: - Меню Edit, щоб у полях працювали ⌘C/⌘V/⌘A

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Вийти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
