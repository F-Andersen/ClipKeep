import SwiftUI

/// Форма як у апаратного вирізу: увігнуті «плечі» зверху (окремо зліва/справа) і круглі кути знизу.
struct NotchShape: Shape {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topLeft, topRight), bottom) }
        set {
            topLeft = newValue.first.first
            topRight = newValue.first.second
            bottom = newValue.second
        }
    }

    func path(in r: CGRect) -> Path {
        let tl = max(0, min(topLeft, r.width / 4))
        let tr = max(0, min(topRight, r.width / 4))
        let b = max(0, min(bottom, (r.width - tl - tr) / 2, r.height - max(tl, tr)))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        if tl > 0 {
            p.addQuadCurve(to: CGPoint(x: r.minX + tl, y: r.minY + tl), control: CGPoint(x: r.minX + tl, y: r.minY))
        }
        p.addLine(to: CGPoint(x: r.minX + tl, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + tl + b, y: r.maxY), control: CGPoint(x: r.minX + tl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - tr, y: r.maxY - b), control: CGPoint(x: r.maxX - tr, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY + tr))
        if tr > 0 {
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - tr, y: r.minY))
        }
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var model: AppModel
    var onTap: () -> Void
    var onBackgroundTap: () -> Void

    var body: some View {
        let size = state.shapeSize
        let shape = NotchShape(topLeft: state.leftTopR, topRight: state.rightTopR, bottom: state.bottomR)
        let lift = !state.expanded && state.hovering && state.hasEars

        ZStack(alignment: .top) {
            if state.expanded {
                // клік у прозорий край вікна — згорнути
                Color.black.opacity(0.001)
                    .onTapGesture(perform: onBackgroundTap)
            }

            ZStack(alignment: .top) {
                Color.black
                if state.expanded {
                    expandedContent
                        .transition(.opacity.animation(.easeOut(duration: 0.2).delay(0.08)))
                } else if state.hasNotch {
                    CollapsedBar(state: state, model: model)
                        .padding(.leading, state.leftTopR)
                        .padding(.trailing, state.rightTopR)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { if !state.expanded { onTap() } }
            .shadow(color: .black.opacity(state.expanded ? 0.5 : (lift ? 0.35 : 0)),
                    radius: state.expanded ? 18 : 4, y: state.expanded ? 8 : 1)
            .scaleEffect(lift ? 1.05 : 1, anchor: .top)
            .offset(x: state.shapeOffsetX)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: state.hovering)
    }

    private var expandedContent: some View {
        let inner = NotchState.panelWidth - NotchState.expandedTopR * 2 - 12
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("NotchClip")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: state.notchSize.width + 12)
                Text("⇧⌘V")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(width: inner, height: state.notchSize.height)

            ContentView(model: model)
                .frame(width: inner, height: NotchState.panelBody - 10)
        }
    }
}

/// Згорнутий стан: виріз + «вушка» (іконка зліва, лічильник справа), якщо для них є місце.
struct CollapsedBar: View {
    @ObservedObject var state: NotchState
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if state.earLeft > 0 {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(state.hovering ? 1 : 0.85))
                        .frame(width: state.earLeft)
                }
                Spacer(minLength: 0)
                if state.earRight > 0 {
                    Text("\(model.history.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(state.hovering ? 0.8 : 0.5))
                        .frame(width: state.earRight)
                }
            }
            .frame(height: state.notchSize.height)

            if state.flashing {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Скопійовано")
                        .foregroundStyle(.white)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .fixedSize()
                .frame(height: NotchState.flashHeight)
                .frame(maxWidth: .infinity)
                .offset(x: -state.collapsedCenterOffset)   // по центру під камерою
                .transition(.opacity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }
}
