#if DEBUG
import SwiftUI

struct TerminalSpikeView: View {
    var body: some View {
        SwiftTermHostingView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
