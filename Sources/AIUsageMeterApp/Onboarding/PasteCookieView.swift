import SwiftUI

struct PasteCookieView: View {
    let onSubmit: (String) -> Void
    let isBusy: Bool

    @State private var sessionKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In a browser logged into claude.ai: open DevTools → Application → Cookies → claude.ai, and copy the value of `sessionKey` (starts with `sk-ant-sid…`).")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("sessionKey cookie value", text: $sessionKey)
                .textFieldStyle(.roundedBorder)

            Button("Add Account") {
                onSubmit(sessionKey)
            }
            .disabled(isBusy || sessionKey.isEmpty)
        }
    }
}
