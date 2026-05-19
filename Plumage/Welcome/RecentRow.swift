import SwiftUI

struct RecentRow: View {
    let item: RecentItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                Text((item.url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // Hover-tooltip exposes the full project path when the row is too
        // narrow to display it (long paths truncate via `.truncationMode`).
        .help(item.url.path)
    }
}
