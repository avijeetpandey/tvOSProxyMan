import SwiftUI

struct HeadersTable: View {
    let headers: [HTTPHeaderField]
    @FocusState private var focusedHeader: UUID?

    var body: some View {
        if headers.isEmpty {
            Text("No headers").foregroundStyle(.secondary).italic()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(headers) { header in
                    HStack(alignment: .top, spacing: 16) {
                        Text(header.name)
                            .font(.system(.callout, design: .monospaced).bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 240, alignment: .leading)
                            .lineLimit(2)

                        Text(header.value)
                            .font(.system(.callout, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // textSelection not available on tvOS
                            .lineLimit(3)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(focusedHeader == header.id
                                  ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .focused($focusedHeader, equals: header.id)
                    .focusable()

                    if header.id != headers.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }
}
