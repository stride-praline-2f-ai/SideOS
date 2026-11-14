import SwiftUI

struct TahoeHTTPAuthentication: Identifiable {
    let id = UUID()
    var origin: String
    var user = ""
    var retry = false
    var completion: (URLCredential?) -> Void
}

/// MacVue field/secure-field appearance with native secure text entry. This
/// presents real WebKit HTTP authentication, without saving a password file.
struct TahoeAuthenticationView: View {
    let request: TahoeHTTPAuthentication
    let complete: (URLCredential?) -> Void
    @State private var user = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.tahoeWindowActive) private var windowActive
    private enum Field: Hashable { case user, password }
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) { Image(systemName: "lock.shield").font(.title).foregroundStyle(TahoeDesign.accent); Text(TahoeStrings.ui("Sign in to website")).font(.system(size: 15, weight: .semibold)) }
                Text(request.origin).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                if request.retry { Text(TahoeStrings.ui("The website did not accept those credentials. Try again.")).font(.system(size: 12)).foregroundStyle(.red) }
                TextField(TahoeStrings.ui("Username"), text: $user).textContentType(.username).textFieldStyle(.plain).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .user)
                    .tahoeField(focused: focus == .user).onSubmit { focus = .password }
                SecureField(TahoeStrings.ui("Password"), text: $password).textContentType(.password).textFieldStyle(.plain).focused($focus, equals: .password)
                    .tahoeField(focused: focus == .password).onSubmit { submit() }
                HStack {
                    Spacer()
                    Button(TahoeStrings.ui("Cancel")) { focus = nil; complete(nil) }.buttonStyle(TahoeControlStyle()).keyboardShortcut(.cancelAction)
                    Button(TahoeStrings.ui("Sign In")) { submit() }.buttonStyle(TahoeControlStyle(variant: .accent)).disabled(user.isEmpty).keyboardShortcut(.defaultAction)
                }.tahoeGlassGroup().padding(.top, 4)
            }.padding(22).frame(maxWidth: 360).background(TahoeDesign.window, in: RoundedRectangle(cornerRadius: 14)).shadow(radius: 20).padding(16)
        }.onAppear { user = request.user; focus = windowActive && windowVisible ? (user.isEmpty ? .user : .password) : nil }
            .onChange(of: windowVisible) { _, visible in if !visible { focus = nil } }
            .onChange(of: windowActive) { _, active in if !active { focus = nil } }
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
    }
    private func submit() { guard !user.isEmpty else { return }; focus = nil; complete(URLCredential(user: user, password: password, persistence: .forSession)) }
}

