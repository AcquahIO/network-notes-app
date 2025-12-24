import Foundation

@MainActor
final class SessionListViewModel: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private let store = LocalStore.shared
    private let network = NetworkMonitor.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if network.isOnline {
                sessions = try await api.fetchSessions()
                for session in sessions {
                    if let detail = try? await api.fetchSessionDetail(id: session.id) {
                        await store.saveSessionDetail(detail, syncState: session.syncState)
                    }
                }
            } else {
                sessions = await store.listSessions()
            }
        } catch {
            errorMessage = error.localizedDescription
            if sessions.isEmpty {
                sessions = await store.listSessions()
            }
        }
    }
}
