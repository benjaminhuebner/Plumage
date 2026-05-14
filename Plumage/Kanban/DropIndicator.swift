import SwiftUI

struct DropIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        DropIndicator()
        DropIndicator()
            .frame(width: 200)
    }
    .padding()
}
