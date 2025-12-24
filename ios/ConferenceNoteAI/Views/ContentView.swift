import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var sessionListVM = SessionListViewModel()
    @StateObject private var studyVM = StudyViewModel()
    @State private var showRecorder = false
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var syncManager = SyncManager.shared
    @State private var pendingShareToken: String?

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient().ignoresSafeArea()
            if authVM.isAuthenticated {
                TabView {
                    NavigationStack {
                        SessionListView(viewModel: sessionListVM, showRecorder: $showRecorder)
                    }
                    .tabItem { Label("Home", systemImage: "house.fill") }

                    NavigationStack {
                        StudyView(viewModel: studyVM)
                    }
                    .tabItem { Label("Study", systemImage: "book.fill") }
                }
                .tint(AppColors.accent)
                .sheet(isPresented: $showRecorder, onDismiss: {
                    Task {
                        await sessionListVM.load()
                        await studyVM.load()
                    }
                }) {
                    RecordingSheet()
                        .presentationDetents([.large])
                        .presentationBackground(AppColors.background)
                }
            } else {
                AuthView()
            }
        }
        .onOpenURL { url in
            pendingShareToken = shareToken(from: url)
        }
        .sheet(isPresented: Binding(
            get: { pendingShareToken != nil && authVM.isAuthenticated },
            set: { if !$0 { pendingShareToken = nil } }
        )) {
            if let token = pendingShareToken {
                ImportSessionView(token: token)
            }
        }
        .onChange(of: networkMonitor.isOnline) { isOnline in
            if isOnline {
                Task { await syncManager.processQueue() }
            }
        }
        .task {
            if networkMonitor.isOnline {
                await syncManager.processQueue()
            }
        }
    }

    private func shareToken(from url: URL) -> String? {
        guard url.scheme == "conferencenoteai" else { return nil }
        guard url.host == "share" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "token" })?.value
    }
}
