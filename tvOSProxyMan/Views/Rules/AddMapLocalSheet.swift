import SwiftUI

struct AddMapLocalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern      = ""
    @State private var statusCode   = "200"
    @State private var contentType  = "application/json"
    @State private var responseBody = "{\n  \n}"
    @FocusState private var focusedField: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("URL Pattern") {
                    TextField("*.example.com/api/data", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                        .focused($focusedField, equals: 0)
                }
                Section("Response") {
                    HStack {
                        Text("Status Code")
                        Spacer()
                        TextField("200", text: $statusCode)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: 1)
                    }
                    HStack {
                        Text("Content-Type")
                        Spacer()
                        TextField("application/json", text: $contentType)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 280)
                            .focused($focusedField, equals: 2)
                    }
                }
                Section("Response Body") {
                    TextField("JSON body", text: $responseBody, axis: .vertical)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(8...)
                        .focused($focusedField, equals: 3)
                }
            }
            .navigationTitle("Add Map Local Rule")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        MapLocalEngine.shared.addRule(
                            urlPattern:   pattern.trimmingCharacters(in: .whitespaces),
                            responseBody: responseBody,
                            statusCode:   Int(statusCode) ?? 200,
                            contentType:  contentType.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { focusedField = 0 }
    }
}
