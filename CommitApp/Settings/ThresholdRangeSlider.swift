import SwiftUI
import CommitCore

/// Two boundaries on one track; values are the number of missed habits at each boundary.
struct ThresholdRangeSlider: View {
    @Binding var yellow: Int
    @Binding var red: Int
    @State private var upperBound = 10

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 24)
            let yellowX = 12 + width * CGFloat(yellow) / CGFloat(upperBound)
            let redX = 12 + width * CGFloat(red) / CGFloat(upperBound)
            let centerY = geometry.size.height / 2
            ZStack(alignment: .leading) {
                Capsule().fill(InformativeThresholds.redColor)
                    .frame(width: width, height: 8).offset(x: 12)
                Rectangle().fill(InformativeThresholds.yellowColor)
                    .frame(width: max(0, redX - yellowX), height: 8).offset(x: yellowX)
                Capsule().fill(InformativeThresholds.allDoneColor)
                    .frame(width: max(0, yellowX - 12), height: 8).offset(x: 12)
                thumb("Yellow starts at", value: yellow, x: yellowX, y: centerY, width: width, isYellow: true)
                thumb("Red starts at", value: red, x: redX, y: centerY, width: width, isYellow: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: "thresholdTrack")
        }
        .onAppear { updateUpperBound() }
    }

    private func thumb(_ label: String, value: Int, x: CGFloat, y: CGFloat, width: CGFloat, isYellow: Bool) -> some View {
        Circle()
            .fill(.background)
            .overlay(Circle().strokeBorder(isYellow ? InformativeThresholds.yellowColor : InformativeThresholds.redColor, lineWidth: 3))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("thresholdTrack"))
                .onChanged { gesture in
                    let fraction = min(1, max(0, (gesture.location.x - 12) / width))
                    setValue(Int((fraction * CGFloat(upperBound)).rounded()), isYellow: isYellow)
                }
                .onEnded { _ in updateUpperBound() })
            .focusable()
            .onMoveCommand { direction in
                if direction == .left { adjust(-1, isYellow: isYellow) }
                if direction == .right { adjust(1, isYellow: isYellow) }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(value) missed habits")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(1, isYellow: isYellow)
                case .decrement: adjust(-1, isYellow: isYellow)
                @unknown default: break
                }
            }
    }

    private func setValue(_ value: Int, isYellow: Bool) {
        if isYellow { yellow = min(red - 1, max(1, value)) }
        else { red = min(100, max(yellow + 1, value)) }
    }

    private func adjust(_ delta: Int, isYellow: Bool) {
        setValue((isYellow ? yellow : red) + delta, isYellow: isYellow)
        updateUpperBound()
    }

    private func updateUpperBound() {
        upperBound = max(10, min(100, red + 2))
    }
}
