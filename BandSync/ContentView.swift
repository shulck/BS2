//
//  ContentView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 31.03.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var isRefreshing = false

    var body: some View {
        Group {
            if isRefreshing {
                // Show loading screen while checking auth state
                LoadingView()
            } else if !appState.isLoggedIn {
                // Show login view if not logged in
                LoginView()
                    .transition(.opacity)
            } else if appState.user?.groupId == nil {
                // User is logged in but doesn't have a group
                GroupSelectionView()
                    .transition(.opacity)
            } else {
                // User is logged in and has a group
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: appState.isLoggedIn)
        .animation(.easeInOut, value: appState.user?.groupId)
        .onAppear {
            refreshState()
        }
    }
    
    private func refreshState() {
        print("ContentView: refreshing state")
        isRefreshing = true
        
        // Force refresh auth state with completion handler
        appState.refreshAuthState {
            // Add slight delay to allow UI to update smoothly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRefreshing = false
                print("ContentView: refresh completed - isLoggedIn: \(appState.isLoggedIn), hasGroup: \(appState.user?.groupId != nil)")
            }
        }
    }
}

// Loading view component
struct LoadingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading...")
                .font(.title2)
                .padding()
        }
    }
}
