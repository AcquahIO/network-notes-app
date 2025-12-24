import Foundation

@MainActor
final class StudyViewModel: ObservableObject {
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
                sessions = try await api.fetchStudySessions()
            } else {
                sessions = await store.listSessions().filter { $0.status == .ready }
            }
        } catch {
            errorMessage = error.localizedDescription
            if sessions.isEmpty {
                sessions = await store.listSessions().filter { $0.status == .ready }
            }
        }
    }
}
