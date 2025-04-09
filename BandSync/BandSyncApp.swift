//
//  BandSyncApp.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import SwiftUI
import FirebaseCore

@main
struct BandSyncApp: App {
    // Register AppDelegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        // Note: Firebase is initialized in AppDelegate
        print("BandSyncApp: initialized")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppState.shared)
                .onAppear {
                    print("BandSyncApp: ContentView appeared")
                }
        }
    }
}
