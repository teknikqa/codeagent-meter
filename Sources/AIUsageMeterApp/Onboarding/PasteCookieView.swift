import SwiftUI

struct PasteCookieView: View {
    let onSubmit: (String) -> Void
    let isBusy: Bool

    @State private var sessionKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In a browser logged into claude.ai: open DevTools → Application → Cookies → claude.ai and copy the `sessionKey` value, or Network tab → any request → copy the full `Cookie` request header. Either works.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("sessionKey cookie value or full Cookie header", text: $sessionKey)
                .textFieldStyle(.roundedBorder)

            Button("Add Account") {
                onSubmit(sessionKey)
            }
            .disabled(isBusy || sessionKey.isEmpty)
        }
    }
}
