import SwiftUI
import CommitCore

/// Card/surface background that adapts to the chosen `AppearanceStyle`.
///
/// - `.minimalist`: the original flat, low-contrast fill.
/// - `.macOS`: a frosted `.regularMaterial` card with a hairline border and soft drop shadow,
///   the way panels look in System Settings and other native apps.
struct SurfaceBackground: ViewModifier {
    let style: AppearanceStyle
    var cornerRadius: CGFloat = 12
    /// Fill opacity for the minimalist flat surface (some surfaces are a touch more prominent).
    var minimalOpacity: Double = 0.08

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        switch style {
        case .minimalist:
            content
                .background(Color.secondary.opacity(minimalOpacity))
                .clipShape(shape)
        case .macOS:
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
    }
}

/// A Finder-style hover highlight for list rows. Only active for the macOS style; when disabled
/// it leaves the row untouched so the minimalist layout keeps its exact spacing.
struct RowHoverHighlight: ViewModifier {
    let enabled: Bool
    @State private var hovering = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.06 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        } else {
            content
        }
    }
}

extension View {
    /// Wrap a card/panel in the surface treatment for the given appearance style.
    func surface(_ style: AppearanceStyle, cornerRadius: CGFloat = 12, minimalOpacity: Double = 0.08) -> some View {
        modifier(SurfaceBackground(style: style, cornerRadius: cornerRadius, minimalOpacity: minimalOpacity))
    }

    /// Add a hover highlight to a list row (macOS style only).
    func rowHover(_ enabled: Bool) -> some View {
        modifier(RowHoverHighlight(enabled: enabled))
    }
}
