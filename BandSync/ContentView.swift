// ContentView.swift - исправленная версия
import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            if isRefreshing {
                ProgressView("Загрузка...")
            } else if !appState.isLoggedIn {
                LoginView()
            } else if appState.user?.groupId == nil {
                GroupSelectionView()
            } else if appState.isPendingApproval {
                PendingApprovalView()
            } else {
                MainTabView()
            }
        }
        .onAppear {
            refreshState()
        }
    }
    
    private func refreshState() {
        isRefreshing = true
        appState.refreshAuthState {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRefreshing = false
            }
        }
    }
}
