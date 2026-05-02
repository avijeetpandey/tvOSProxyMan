import SwiftUI

struct EmptyDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Select a Request")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
