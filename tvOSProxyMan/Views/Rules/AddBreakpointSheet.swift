import SwiftUI

struct AddBreakpointSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern = ""
    @State private var methodsText = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("URL Pattern") {
                    TextField("*.example.com/api/* or api.example.com", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                        .focused($focused)
                }
                Section {
                    TextField("GET, POST  (leave empty for all)", text: $methodsText)
                } header: {
                    Text("Methods")
                } footer: {
                    Text("Comma-separated HTTP methods to intercept. Leave blank to match all.")
                }
            }
            .navigationTitle("Add Breakpoint")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let methods = Set(
                            methodsText.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                                .filter { !$0.isEmpty }
                        )
                        BreakpointEngine.shared.addBreakpoint(
                            urlPattern: pattern.trimmingCharacters(in: .whitespaces),
                            methods: methods
                        )
                        dismiss()
                    }
                    .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { focused = true }
    }
}
