//
//  UserService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class UserService: ObservableObject {
    static let shared = UserService()

    @Published var currentUser: UserModel?

    private let db = Firestore.firestore()

    private init() {
        print("UserService: initialized")
    }

    // Check if user exists and create if not
    func ensureUserExists(uid: String, email: String, completion: @escaping (Result<UserModel, Error>) -> Void) {
        print("UserService: ensuring user exists with UID: \(uid)")
        
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("UserService: error checking user: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if let document = snapshot, document.exists {
                print("UserService: user document exists, attempting to decode")
                
                do {
                    // Try to get existing user
                    let user = try document.data(as: UserModel.self)
                    print("UserService: user successfully decoded: \(user.name)")
                    self?.currentUser = user
                    completion(.success(user))
                } catch {
                    print("UserService: error decoding user: \(error.localizedDescription)")
                    print("UserService: creating new user profile to replace existing document")

                    // If document exists but decoding failed,
                    // create a new document, completely replacing the existing one
                    self?.createUserProfile(uid: uid, email: email, completion: completion)
                }
            } else {
                print("UserService: user doesn't exist, creating new profile")
                // User doesn't exist, create new
                self?.createUserProfile(uid: uid, email: email, completion: completion)
            }
        }
    }

    // Create new user profile
    private func createUserProfile(uid: String, email: String, completion: @escaping (Result<UserModel, Error>) -> Void) {
        print("UserService: creating new user profile for UID: \(uid)")
        
        // Create basic profile
        let newUser = UserModel(
            id: uid,
            email: email,
            name: email.components(separatedBy: "@").first ?? "User",
            phone: "",
            groupId: nil,
            role: .member
        )

        do {
            try db.collection("users").document(uid).setData(from: newUser) { [weak self] error in
                if let error = error {
                    print("UserService: error creating profile: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                print("UserService: profile created successfully")
                self?.currentUser = newUser
                completion(.success(newUser))
            }
        } catch {
            print("UserService: error serializing profile: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }

    // Get user by ID with improved logic
    func fetchUser(uid: String, completion: @escaping (Result<UserModel, Error>) -> Void) {
        print("UserService: fetching user with UID: \(uid)")
        
        db.collection("users").document(uid).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("UserService: error getting user: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            if let document = snapshot, document.exists {
                print("UserService: user document exists, attempting to decode")
                
                do {
                    let user = try document.data(as: UserModel.self)
                    print("UserService: user successfully decoded: \(user.name)")
                    self?.currentUser = user
                    completion(.success(user))
                } catch {
                    print("UserService: error decoding user: \(error.localizedDescription)")

                    // Try to get data manually if decoding failed
                    let data = document.data()
                    if let email = data?["email"] as? String {
                        print("UserService: manual data extraction successful, creating new profile")
                        self?.ensureUserExists(uid: uid, email: email, completion: completion)
                    } else {
                        print("UserService: manual data extraction failed")
                        completion(.failure(error))
                    }
                }
            } else {
                print("UserService: user document doesn't exist")
                if let email = Auth.auth().currentUser?.email {
                    print("UserService: creating new profile using Firebase auth email")
                    self?.ensureUserExists(uid: uid, email: email, completion: completion)
                } else {
                    let error = NSError(domain: "UserService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
                    print("UserService: no email available to create profile")
                    completion(.failure(error))
                }
            }
        }
    }

    func updateUserGroup(groupId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            let error = NSError(domain: "UserService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Current user not found"])
            completion(.failure(error))
            return
        }

        print("UserService: updating user group to: \(groupId)")
        
        db.collection("users").document(uid).updateData([
            "groupId": groupId
        ]) { [weak self] error in
            if let error = error {
                print("UserService: error updating group ID: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("UserService: group ID updated successfully")
                
                // Update local data
                if let user = self?.currentUser {
                    // Create new instance with updated groupId
                    let updatedUser = UserModel(
                        id: user.id ?? "",
                        email: user.email,
                        name: user.name,
                        phone: user.phone,
                        groupId: groupId,
                        role: user.role
                    )
                    self?.currentUser = updatedUser
                }
                completion(.success(()))
            }
        }
    }

    func clearUserGroup(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            let error = NSError(domain: "UserService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not found"])
            completion(.failure(error))
            return
        }

        print("UserService: clearing user's group ID")
        
        db.collection("users").document(uid).updateData([
            "groupId": NSNull()
        ]) { [weak self] error in
            if let error = error {
                print("UserService: error clearing group ID: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("UserService: group ID cleared successfully")
                
                // Update local data
                if let user = self?.currentUser {
                    // Create new instance with cleared groupId
                    let updatedUser = UserModel(
                        id: user.id ?? "",
                        email: user.email,
                        name: user.name,
                        phone: user.phone,
                        groupId: nil,
                        role: user.role
                    )
                    self?.currentUser = updatedUser
                }

                completion(.success(()))
            }
        }
    }

    // Additional methods

    func fetchUsers(ids: [String], completion: @escaping ([UserModel]) -> Void) {
        guard !ids.isEmpty else {
            print("UserService: fetchUsers called with empty IDs array")
            completion([])
            return
        }

        print("UserService: fetching \(ids.count) users")
        
        // Firestore limit: can request maximum 10 documents at once
        let batchSize = 10
        var result: [UserModel] = []
        let dispatchGroup = DispatchGroup()

        // Split array into batches of 10 elements
        for i in stride(from: 0, to: ids.count, by: batchSize) {
            let end = min(i + batchSize, ids.count)
            let batch = Array(ids[i..<end])

            dispatchGroup.enter()
            print("UserService: processing batch of \(batch.count) users")
            
            db.collection("users")
                .whereField(FieldPath.documentID(), in: batch)
                .getDocuments { snapshot, error in
                    defer { dispatchGroup.leave() }

                    if let error = error {
                        print("UserService: error getting users: \(error.localizedDescription)")
                        return
                    }

                    if let documents = snapshot?.documents {
                        let users = documents.compactMap { doc -> UserModel? in
                            do {
                                let user = try doc.data(as: UserModel.self)
                                print("UserService: successfully decoded user: \(user.name)")
                                return user
                            } catch {
                                print("UserService: error decoding user: \(error.localizedDescription)")

                                // Manual user assembly if decoding failed
                                let data = doc.data()
                                if let email = data["email"] as? String,
                                   let name = data["name"] as? String {
                                    let id = doc.documentID
                                    let phone = data["phone"] as? String ?? ""
                                    let groupId = data["groupId"] as? String
                                    let roleString = data["role"] as? String ?? "Member"
                                    let role = UserModel.UserRole(rawValue: roleString) ?? .member

                                    print("UserService: manually created user: \(name)")
                                    return UserModel(
                                        id: id,
                                        email: email,
                                        name: name,
                                        phone: phone,
                                        groupId: groupId,
                                        role: role
                                    )
                                }
                                return nil
                            }
                        }
                        result.append(contentsOf: users)
                    }
                }
        }

        dispatchGroup.notify(queue: .main) {
            print("UserService: completed fetching \(result.count) users")
            completion(result)
        }
    }

    func findUserByEmail(_ email: String, completion: @escaping (Result<UserModel?, Error>) -> Void) {
        print("UserService: finding user by email: \(email)")
        
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("UserService: error finding user: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                if let document = snapshot?.documents.first {
                    print("UserService: found user document, attempting to decode")
                    
                    do {
                        let user = try document.data(as: UserModel.self)
                        print("UserService: successfully decoded user: \(user.name)")
                        completion(.success(user))
                    } catch {
                        print("UserService: error converting user data: \(error.localizedDescription)")

                        // Manual user assembly if decoding failed
                        let data = document.data()
                        if let email = data["email"] as? String,
                           let name = data["name"] as? String {
                            let id = document.documentID
                            let phone = data["phone"] as? String ?? ""
                            let groupId = data["groupId"] as? String
                            let roleString = data["role"] as? String ?? "Member"
                            let role = UserModel.UserRole(rawValue: roleString) ?? .member

                            print("UserService: manually created user: \(name)")
                            let user = UserModel(
                                id: id,
                                email: email,
                                name: name,
                                phone: phone,
                                groupId: groupId,
                                role: role
                            )
                            completion(.success(user))
                        } else {
                            completion(.failure(error))
                        }
                    }
                } else {
                    print("UserService: no user found with email: \(email)")
                    completion(.success(nil))
                }
            }
    }
}
