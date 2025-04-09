//
//  AuthViewModel.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import Combine

final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var name = ""
    @Published var phone = ""
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Login method with improved error handling and debug info
    func login() {
        print("AuthViewModel: login attempt with email: \(email)")
        isLoading = true
        errorMessage = nil
        
        AuthService.shared.loginUser(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success:
                    print("AuthViewModel: login successful, updating auth state")
                    self?.isAuthenticated = true
                    // Update global state
                    AppState.shared.refreshAuthState(completion: {
                        print("AuthViewModel: AppState refresh completed")
                    })
                    
                case .failure(let error):
                    print("AuthViewModel: login failed with error: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Registration method with improved error handling
    func register() {
        print("AuthViewModel: registration attempt with email: \(email)")
        isLoading = true
        errorMessage = nil
        
        AuthService.shared.registerUser(email: email, password: password, name: name, phone: phone) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success:
                    print("AuthViewModel: registration successful")
                    self?.isAuthenticated = true
                    // Update global state
                    AppState.shared.refreshAuthState()
                    
                case .failure(let error):
                    print("AuthViewModel: registration failed with error: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // Password reset method with improved error handling
    func resetPassword() {
        print("AuthViewModel: password reset attempt for email: \(email)")
        isLoading = true
        errorMessage = nil
        
        AuthService.shared.resetPassword(email: email) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success:
                    print("AuthViewModel: password reset email sent successfully")
                    self?.errorMessage = "Password reset email sent"
                    
                case .failure(let error):
                    print("AuthViewModel: password reset failed with error: \(error.localizedDescription)")
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
