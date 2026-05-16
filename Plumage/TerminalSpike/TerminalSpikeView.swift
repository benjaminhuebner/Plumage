#if DEBUG
import SwiftUI

struct TerminalSpikeView: View {
    var body: some View {
        SwiftTermHostingView()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
