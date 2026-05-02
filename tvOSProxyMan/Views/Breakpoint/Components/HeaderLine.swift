import SwiftUI

struct HeaderLine: View {
    let name: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                // textSelection not available on tvOS
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
