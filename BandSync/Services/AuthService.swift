//
//  AuthService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class AuthService {
    static let shared = AuthService()
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    
    private init() {
        print("AuthService: initialized")
    }
    
    func registerUser(email: String, password: String, name: String, phone: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("AuthService: starting user registration with email \(email)")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        auth.createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error {
                print("AuthService: error creating user: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let uid = result?.user.uid else {
                print("AuthService: UID missing after user creation")
                let error = NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User UID is missing after successful registration"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            print("AuthService: user created with UID: \(uid)")

            let user = UserModel(
                id: uid,
                email: email,
                name: name,
                phone: phone,
                groupId: nil,
                role: .member
            )
            
            // Serialize model and save
            do {
                try self?.db.collection("users").document(uid).setData(from: user) { error in
                    if let error = error {
                        print("AuthService: error saving user data: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    } else {
                        print("AuthService: user data successfully saved")
                        DispatchQueue.main.async {
                            completion(.success(()))
                        }
                    }
                }
            } catch {
                print("AuthService: error serializing user data: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func loginUser(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("AuthService: attempting to log in user with email \(email)")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        auth.signIn(withEmail: email, password: password) { [weak self] authResult, error in
            if let error = error {
                print("AuthService: error logging in: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let uid = authResult?.user.uid else {
                print("AuthService: UID missing after login")
                let error = NSError(domain: "AuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User UID is missing after successful login"])
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            print("AuthService: user login successful with UID: \(uid)")
            
            // After successful login, ensure user exists
            UserService.shared.ensureUserExists(uid: uid, email: email) { result in
                switch result {
                case .success(let user):
                    print("AuthService: user profile found/created: \(user.name), role: \(user.role.rawValue)")
                    DispatchQueue.main.async {
                        completion(.success(()))
                    }
                case .failure(let error):
                    print("AuthService: error ensuring user exists: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    func resetPassword(email: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("AuthService: sending password reset request for email \(email)")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        auth.sendPasswordReset(withEmail: email) { error in
            if let error = error {
                print("AuthService: error resetting password: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            } else {
                print("AuthService: password reset request sent successfully")
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            }
        }
    }

    func signOut(completion: @escaping (Result<Void, Error>) -> Void) {
        print("AuthService: attempting to log out user")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        do {
            try auth.signOut()
            print("AuthService: user logout successful")
            DispatchQueue.main.async {
                completion(.success(()))
            }
        } catch {
            print("AuthService: error logging out: \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    func isUserLoggedIn() -> Bool {
        print("AuthService: checking user authorization")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        let isLoggedIn = auth.currentUser != nil
        print("AuthService: user is \(isLoggedIn ? "authorized" : "not authorized")")
        return isLoggedIn
    }

    func currentUserUID() -> String? {
        print("AuthService: requesting current user UID")
        
        // Check if Firebase is initialized (don't initialize)
        FirebaseManager.shared.ensureInitialized()
        
        let uid = auth.currentUser?.uid
        if let uid = uid {
            print("AuthService: current user UID: \(uid)")
        } else {
            print("AuthService: current user UID is missing")
        }
        return uid
    }
}
