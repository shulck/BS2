//
//  FirebaseManager.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseCore

class FirebaseManager {
    static let shared = FirebaseManager()
    
    private(set) var isInitialized = false
    
    private init() {
        print("FirebaseManager: instance created")
        // Check if Firebase is already initialized
        if FirebaseApp.app() != nil {
            isInitialized = true
            print("FirebaseManager: Firebase was already initialized by AppDelegate")
        }
    }
    
    // This method won't initialize Firebase again if it's already initialized
    // It will only ensure Firebase is initialized
    func ensureInitialized() {
        print("FirebaseManager: checking initialization")
        if FirebaseApp.app() != nil {
            isInitialized = true
            print("FirebaseManager: Firebase is already initialized")
        } else {
            print("FirebaseManager: WARNING - Firebase wasn't initialized in AppDelegate")
        }
    }
}
