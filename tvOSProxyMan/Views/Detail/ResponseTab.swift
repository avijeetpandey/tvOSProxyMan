import SwiftUI

struct ResponseTab: View {
    let tx: ProxyTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            if tx.responseHeaders.isEmpty && tx.responseBody == nil {
                ContentUnavailableView(
                    "No Response Yet",
                    systemImage: "clock",
                    description: Text("Waiting for the server to respond.")
                )
                .padding(40)
            } else {
                InfoCard(title: "Response Headers") {
                    HeadersTable(headers: tx.responseHeaders)
                }

                if let body = tx.responseBody, !body.isEmpty {
                    InfoCard(title: "Response Body (\(body.count) bytes)") {
                        BodyView(data: body,
                                 contentType: tx.responseHeaders.first(where: {
                                     $0.name.lowercased() == "content-type"
                                 })?.value)
                    }
                }
            }
        }
        .padding(40)
    }
}
