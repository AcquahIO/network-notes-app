import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var user: User?

    private let api = APIClient.shared

    init() {
        if KeychainStorage.shared.loadToken(for: "ConferenceNoteAI.jwt") != nil {
            isAuthenticated = true
        }
    }

    func login() async {
        do {
            let result = try await api.login(email: email, password: password)
            api.setToken(result.token)
            user = result.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func register() async {
        do {
            let result = try await api.register(email: email, password: password)
            api.setToken(result.token)
            user = result.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logout() {
        api.clearToken()
        user = nil
        isAuthenticated = false
    }

    func continueAsGuest() {
        api.enableDemoMode()
        user = User(id: "demo", email: "demo@conference.note.ai")
        isAuthenticated = true
    }
}
