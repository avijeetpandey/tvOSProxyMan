import SwiftUI

struct BodyView: View {
    let data: Data
    let contentType: String?

    private var bodyText: String {
        let ct = (contentType ?? "").lowercased()
        if ct.contains("json"), let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                    options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        if ct.contains("text") || ct.contains("xml") || ct.contains("html") {
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? hexPreview
        }
        return String(data: data, encoding: .utf8) ?? hexPreview
    }

    private var hexPreview: String {
        let bytes = data.prefix(256)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "[\(data.count) bytes — binary content]\n\n\(hex)\(data.count > 256 ? " …" : "")"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(bodyText)
                .font(.system(.caption, design: .monospaced))
                // textSelection not available on tvOS
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 500)
    }
}
