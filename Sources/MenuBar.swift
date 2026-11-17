import AppKit
import ApplicationServices

/// Через Accessibility з'ясовує, скільки вільного місця в меню-барі зліва і справа від вирізу:
/// зліва/справа можуть бути меню активної програми, справа — іконки статусу.
final class MenuBarScanner {
    private let queue = DispatchQueue(label: "notchclip.menubar", qos: .utility)
    private var statusRects: [CGRect] = []          // доступ лише з queue
    private var lastStatusScan = Date.distantPast   // доступ лише з queue

    /// band — смуга меню-бару цього екрана, усе в координатах AX (початок зверху зліва).
    func measure(frontmostPID: pid_t?, statusPIDs: [pid_t], band: CGRect,
                 notchMinX: CGFloat, notchMaxX: CGFloat, rescanStatus: Bool,
                 completion: @escaping (_ freeLeft: CGFloat, _ freeRight: CGFloat) -> Void) {
        queue.async { [self] in
            if rescanStatus || Date().timeIntervalSince(lastStatusScan) > 20 {
                statusRects = statusPIDs.flatMap { Self.itemFrames(pid: $0, attribute: "AXExtrasMenuBar") }
                lastStatusScan = Date()
            }
            var rects = statusRects
            if let frontmostPID {
                rects += Self.itemFrames(pid: frontmostPID, attribute: kAXMenuBarAttribute)
            }
            let free = Self.freeSpace(rects: rects, band: band, notchMinX: notchMinX, notchMaxX: notchMaxX)
            DispatchQueue.main.async { completion(free.left, free.right) }
        }
    }

    static func freeSpace(rects: [CGRect], band: CGRect, notchMinX: CGFloat, notchMaxX: CGFloat)
        -> (left: CGFloat, right: CGFloat) {
        var leftBound = band.minX
        var rightBound = band.maxX
        for r in rects where r.width > 0 && r.height > 0
            && r.minY < band.maxY && r.maxY > band.minY
            && r.minX >= band.minX - 1 && r.maxX <= band.maxX + 1 {
            if r.maxX <= notchMinX + 0.5 {
                leftBound = max(leftBound, r.maxX)
            } else if r.minX >= notchMaxX - 0.5 {
                rightBound = min(rightBound, r.minX)
            } else if r.minX < notchMinX {
                leftBound = notchMinX      // заходить під лівий край вирізу
            } else if r.maxX > notchMaxX {
                rightBound = notchMaxX     // заходить під правий край вирізу
            }
            // повністю під вирізом — невидимий, не заважає
        }
        return (max(0, notchMinX - leftBound), max(0, rightBound - notchMaxX))
    }

    private static func itemFrames(pid: pid_t, attribute: String) -> [CGRect] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar = value(app, attribute),
              CFGetTypeID(bar) == AXUIElementGetTypeID(),
              let items = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return items.compactMap(frame(of:))
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &v) == .success ? v : nil
    }
}
