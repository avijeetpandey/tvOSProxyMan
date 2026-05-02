import SwiftUI

struct BreakpointReadOnlySection: View {
    let req: PausedRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle("Request Headers")
            ForEach(req.transaction.requestHeaders) { h in
                HeaderLine(name: h.name, value: h.value)
            }

            if let body = req.transaction.requestBody,
               let text = String(data: body, encoding: .utf8), !text.isEmpty {
                SectionTitle("Request Body")
                Text(prettyJSON(text))
                    .font(.system(.caption, design: .monospaced))
                    // textSelection not available on tvOS
            }
        }
    }

    private func prettyJSON(_ raw: String) -> String {
        guard let d = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else { return raw }
        return str
    }
}
