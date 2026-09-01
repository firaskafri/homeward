import SwiftUI

struct InlineErrorView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Spacer()
            Button("Dismiss", action: dismiss)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline.error")
    }
}
