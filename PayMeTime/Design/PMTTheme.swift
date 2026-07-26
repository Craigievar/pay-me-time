import SwiftUI

enum PMTTheme {
    static let ivory = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let paper = Color(red: 0.99, green: 0.982, blue: 0.965)
    static let charcoal = Color(red: 0.153, green: 0.145, blue: 0.129)
    static let amber = Color(red: 0.784, green: 0.475, blue: 0.122)
    static let sage = Color(red: 0.424, green: 0.49, blue: 0.392)
    static let stone = Color(red: 0.58, green: 0.55, blue: 0.50)

    static var canvas: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.08, green: 0.075, blue: 0.068, alpha: 1)
                : UIColor(red: 0.965, green: 0.945, blue: 0.91, alpha: 1)
        })
    }

    static var surface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.14, green: 0.13, blue: 0.12, alpha: 1)
                : UIColor(red: 0.99, green: 0.982, blue: 0.965, alpha: 1)
        })
    }
}
struct PMTCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(PMTTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.primary.opacity(0.09), lineWidth: 1)
            }
    }
}

extension View {
    func pmtCard() -> some View {
        modifier(PMTCard())
    }

    func pmtPrimaryButton() -> some View {
        font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(PMTTheme.amber)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
