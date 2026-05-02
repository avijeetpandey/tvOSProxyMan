import SwiftUI

struct RequestTab: View {
    let tx: ProxyTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            InfoCard(title: "Request Headers") {
                HeadersTable(headers: tx.requestHeaders)
            }

            if let body = tx.requestBody, !body.isEmpty {
                InfoCard(title: "Request Body (\(body.count) bytes)") {
                    BodyView(data: body,
                             contentType: tx.requestHeaders.first(where: {
                                 $0.name.lowercased() == "content-type"
                             })?.value)
                }
            }
        }
        .padding(40)
    }
}
