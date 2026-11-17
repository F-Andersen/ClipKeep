import AppKit
import SwiftUI

/// Стан «острівця» біля вирізу камери.
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var hovering = false
    @Published var flashing = false
    @Published var hasNotch = true
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var notchMidX: CGFloat = 0     // центр вирізу, екранні координати
    @Published var windowMidX: CGFloat = 0    // центр нашого вікна, екранні координати
    /// Ширина «вушок»: підлаштовується під вільне місце в меню-барі (0 — сховано).
    @Published var earLeft: CGFloat = NotchState.maxEar
    @Published var earRight: CGFloat = 0

    static let maxEar: CGFloat = 30
    static let minEar: CGFloat = 22
    static let shoulder: CGFloat = 6          // увігнуті «плечі» зверху
    static let hoverMargin: CGFloat = 8       // запас вікна під анімацію наведення
    static let flashHeight: CGFloat = 22      // «Скопійовано» виїжджає під виріз
    static let panelWidth: CGFloat = 440
    static let panelBody: CGFloat = 470       // висота панелі під вирізом
    static let expandedTopR: CGFloat = 14
    static let expandedBottomR: CGFloat = 26
    static let collapsedBottomR: CGFloat = 10

    var hasEars: Bool { earLeft > 0 || earRight > 0 }
    private var leftShoulder: CGFloat { earLeft > 0 ? Self.shoulder : 0 }
    private var rightShoulder: CGFloat { earRight > 0 ? Self.shoulder : 0 }

    var leftTopR: CGFloat { expanded ? Self.expandedTopR : leftShoulder }
    var rightTopR: CGFloat { expanded ? Self.expandedTopR : rightShoulder }
    var bottomR: CGFloat { expanded ? Self.expandedBottomR : (flashing ? 14 : Self.collapsedBottomR) }

    /// Наскільки центр згорнутої форми зміщений від центру вирізу (якщо «вушка» різні).
    var collapsedCenterOffset: CGFloat {
        guard hasNotch else { return 0 }
        return ((earRight + rightShoulder) - (earLeft + leftShoulder)) / 2
    }

    var shapeSize: CGSize {
        if expanded {
            return CGSize(width: Self.panelWidth, height: notchSize.height + Self.panelBody)
        }
        guard hasNotch else { return CGSize(width: 120, height: notchSize.height) }
        let width = notchSize.width + earLeft + earRight + leftShoulder + rightShoulder
        return CGSize(width: width, height: notchSize.height + (flashing ? Self.flashHeight : 0))
    }

    /// Зсув форми всередині вікна, щоб її «вирізна» частина завжди була точно над камерою.
    var shapeOffsetX: CGFloat {
        notchMidX + (expanded ? 0 : collapsedCenterOffset) - windowMidX
    }

    // Запас вікна навколо згорнутої форми — лише з боків, де є «вушка»,
    // щоб прозорі краї вікна не перекривали меню.
    var marginLeft: CGFloat { earLeft > 0 ? Self.hoverMargin : 0 }
    var marginRight: CGFloat { earRight > 0 ? Self.hoverMargin : 0 }
    var marginBottom: CGFloat { hasEars ? 6 : 0 }
}

/// Безрамкова панель над меню-баром, яка може приймати клавіатуру, не активуючи застосунок.
final class NotchPanel: NSPanel {
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view, що ловить наведення навіть коли застосунок неактивний і приймає перший клік.
final class NotchHostingView: NSHostingView<NotchView> {
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    required init(rootView: NotchView) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

final class NotchController: NSObject, NSWindowDelegate {
    let state = NotchState()
    private let model: AppModel
    private let panel: NotchPanel
    private let scanner = MenuBarScanner()
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var flashWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var measureTimer: Timer?
    private var measuring = false

    /// Обробник клавіш, поки панель відкрита. true — клавішу оброблено.
    var keyHandler: ((NSEvent) -> Bool)?

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private let collapseAnimation = Animation.spring(response: 0.34, dampingFraction: 0.92)

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        // Над меню-баром. Ставимо останнім: isFloatingPanel тощо перезаписують рівень.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

        let host = NotchHostingView(rootView: NotchView(
            state: state,
            model: model,
            onTap: { [weak self] in self?.toggle() },
            onBackgroundTap: { [weak self] in self?.collapse() }
        ))
        host.onHover = { [weak self] inside in
            guard let self else { return }
            if self.state.hovering != inside { self.state.hovering = inside }
        }
        panel.contentView = host

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        layoutCollapsed()
        startMeasuring()
    }

    var isExpanded: Bool { state.expanded }

    // MARK: - Екран і розміри

    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateMetrics(for screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        let hasNotch: Bool
        let size: CGSize
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            size = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            hasNotch = false
            let menuBar = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
            size = CGSize(width: 0, height: menuBar)
        }
        // присвоюємо лише зміни, щоб не перемальовувати інтерфейс щоразу
        if state.notchMidX != screen.frame.midX { state.notchMidX = screen.frame.midX }
        if state.hasNotch != hasNotch { state.hasNotch = hasNotch }
        if state.notchSize != size { state.notchSize = size }
    }

    private func setWindowFrame(_ frame: NSRect) {
        state.windowMidX = frame.midX
        panel.setFrame(frame, display: true)
    }

    /// Вікно точно навколо згорнутої форми (запас лише там, де є «вушка»).
    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let size = state.shapeSize
        let shapeMinX = state.notchMidX + state.collapsedCenterOffset - size.width / 2
        let x = (shapeMinX - state.marginLeft).rounded(.down)
        let w = (size.width + state.marginLeft + state.marginRight).rounded(.up)
        let h = size.height + state.marginBottom
        return NSRect(x: x, y: screen.frame.maxY - h, width: w, height: h)
    }

    private func layoutCollapsed() {
        guard !state.expanded, let screen = targetScreen else { return }
        updateMetrics(for: screen)
        guard state.hasNotch else {
            panel.orderOut(nil)
            return
        }
        setWindowFrame(collapsedFrame(on: screen))
        panel.orderFrontRegardless()
    }

    @objc private func screensChanged() {
        if !state.expanded { layoutCollapsed() }
        measure(rescanStatus: true)
    }

    // MARK: - Вільне місце в меню-барі

    private func startMeasuring() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appActivated),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.measure(rescanStatus: false) }
        RunLoop.main.add(timer, forMode: .common)
        measureTimer = timer
        measure(rescanStatus: true)
    }

    @objc private func appActivated() {
        measure(rescanStatus: false)
        // меню нової програми можуть з'явитися з невеликою затримкою
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.measure(rescanStatus: false) }
    }

    @objc private func appsChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.measure(rescanStatus: true) }
    }

    private func measure(rescanStatus: Bool) {
        guard !measuring, let screen = targetScreen else { return }
        updateMetricsIfCollapsed(screen)
        guard state.hasNotch else { return }
        guard AXIsProcessTrusted() else {
            // без дозволу не бачимо меню — лишаємо тільки ліве «вушко»
            applyEars(left: NotchState.maxEar, right: 0)
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let band = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                          width: screen.frame.width, height: state.notchSize.height)
        let notchMinX = state.notchMidX - state.notchSize.width / 2
        let statusPIDs = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map(\.processIdentifier)

        measuring = true
        scanner.measure(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                        statusPIDs: statusPIDs, band: band,
                        notchMinX: notchMinX, notchMaxX: notchMinX + state.notchSize.width,
                        rescanStatus: rescanStatus) { [weak self] freeLeft, freeRight in
            guard let self else { return }
            self.measuring = false
            self.applyEars(left: Self.ear(forFree: freeLeft), right: Self.ear(forFree: freeRight))
        }
    }

    private func updateMetricsIfCollapsed(_ screen: NSScreen) {
        if !state.expanded { updateMetrics(for: screen) }
    }

    /// Скільки «вушка» влазить у вільне місце (з урахуванням «плечей» і запасу під наведення).
    private static func ear(forFree free: CGFloat) -> CGFloat {
        let available = (free - NotchState.shoulder - NotchState.hoverMargin - 2).rounded(.down)
        return available >= NotchState.minEar ? min(NotchState.maxEar, available) : 0
    }

    private func applyEars(left: CGFloat, right: CGFloat) {
        guard left != state.earLeft || right != state.earRight else { return }
        state.earLeft = left
        state.earRight = right
        if !state.expanded && !state.flashing {
            shrinkWork?.cancel()
            layoutCollapsed()
        }
    }

    // MARK: - Відкрити / закрити

    func toggle() {
        state.expanded ? collapse() : expand()
    }

    func expand() {
        guard !state.expanded, let screen = targetScreen else { return }
        shrinkWork?.cancel()
        flashWork?.cancel()
        state.flashing = false

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        updateMetrics(for: screen)
        model.prepareForOpen()

        let margin: CGFloat = 30
        let w = NotchState.panelWidth + margin * 2
        let h = state.notchSize.height + NotchState.panelBody + margin
        setWindowFrame(NSRect(x: (state.notchMidX - w / 2).rounded(), y: screen.frame.maxY - h, width: w, height: h))
        panel.allowKey = true
        panel.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [self] in
            withAnimation(expandAnimation) { state.expanded = true }
            model.openCounter += 1
        }
        installMonitors()
    }

    func collapse() {
        guard state.expanded else { return }
        removeMonitors()

        // Повертаємо клавіатуру програмі, з якої відкрили панель
        // (панель лишається видимою, щоб доанімувати згортання).
        panel.allowKey = false
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        if NSApp.isActive { previousApp?.activate(options: []) }

        state.hovering = false
        withAnimation(collapseAnimation) { state.expanded = false }

        let work = DispatchWorkItem { [weak self] in self?.layoutCollapsed() }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    func windowDidResignKey(_ notification: Notification) {
        if state.expanded && panel.allowKey { collapse() }
    }

    /// Коротка анімація «Скопійовано»: виріз виїжджає вниз, не зачіпаючи меню.
    func flash() {
        guard !state.expanded, state.hasNotch, let screen = targetScreen else { return }
        flashWork?.cancel()
        shrinkWork?.cancel()

        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { state.flashing = true }
        setWindowFrame(collapsedFrame(on: screen))

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { self.state.flashing = false }
            let shrink = DispatchWorkItem { [weak self] in self?.layoutCollapsed() }
            self.shrinkWork = shrink
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: shrink)
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    // MARK: - Монітори подій

    private func installMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.state.expanded else { return event }
                return (self.keyHandler?(event) ?? false) ? nil : event
            }
        }
        if clickMonitor == nil {
            // клік у будь-якій іншій програмі — згорнути
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.collapse()
            }
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }
}
