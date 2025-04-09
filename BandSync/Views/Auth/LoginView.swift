//
//  LoginView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import SwiftUI
import LocalAuthentication

struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @State private var showRegister = false
    @State private var showForgotPassword = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("BandSync")
                    .font(.largeTitle.bold())
                    .padding(.top)

                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isLoading)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isLoading)

                Button("Login") {
                    print("Login button tapped")
                    viewModel.login()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty || viewModel.isLoading)

                // Loading indicator
                if viewModel.isLoading {
                    ProgressView("Logging in...")
                        .padding()
                }

                Button("Login with Face ID") {
                    authenticateWithFaceID()
                }
                .disabled(viewModel.isLoading)

                Button("Forgot password?") {
                    showForgotPassword = true
                }
                .padding(.top, 5)
                .disabled(viewModel.isLoading)

                NavigationLink("Registration", destination: RegisterView())
                    .padding(.top)
                    .disabled(viewModel.isLoading)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Login")
            .fullScreenCover(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
        }
        .onAppear {
            // Check if already logged in
            if AuthService.shared.isUserLoggedIn() {
                print("LoginView: User is already logged in")
                viewModel.isAuthenticated = true
                AppState.shared.refreshAuthState()
            } else {
                print("LoginView: User is not logged in")
            }
        }
    }

    private func authenticateWithFaceID() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Login with Face ID") { success, error in
                if success {
                    DispatchQueue.main.async {
                        viewModel.isAuthenticated = true
                        AppState.shared.refreshAuthState()
                    }
                } else if let error = error {
                    DispatchQueue.main.async {
                        viewModel.errorMessage = "Face ID error: \(error.localizedDescription)"
                    }
                }
            }
        } else if let error = error {
            viewModel.errorMessage = "Face ID not available: \(error.localizedDescription)"
        } else {
            viewModel.errorMessage = "Face ID not available"
        }
    }
}
