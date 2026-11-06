import SwiftUI

extension View {
    func surface(cornerRadius: CGFloat = 12, opacity: Double = 0.08) -> some View {
        background(Color.secondary.opacity(opacity), in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
