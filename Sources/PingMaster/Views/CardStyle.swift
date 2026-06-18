import SwiftUI

// Shared card container used across the app for a consistent look.
struct SectionCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
}

extension View {
    func cardBackground(_ opacity: Double = 0.04, cornerRadius: CGFloat = 12) -> some View {
        self.background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.primary.opacity(opacity)))
    }
}
