import SwiftUI

struct InlineErrorView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HomewardCard(padding: HomewardSpacing.medium) {
            HStack(alignment: .top, spacing: HomewardSpacing.medium) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HomewardTone.critical.color)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Something went wrong")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                Button("Dismiss", action: dismiss)
                    .accessibilityHint("Clears this error message")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error")
        .accessibilityIdentifier("inline.error")
    }
}
