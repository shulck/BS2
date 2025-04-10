//
//  AppState.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseAuth
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isLoggedIn = false
    @Published var user: UserModel?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("AppState: initializing")
        refreshAuthState()

        // Subscribe to Firebase auth state changes
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            print("AppState: Firebase auth state changed, user: \(user?.uid ?? "nil")")
            self?.refreshAuthState()
        }
    }

    // Refresh authentication state with debug logs and completion handler
    func refreshAuthState(completion: (() -> Void)? = nil) {
        print("AppState: refreshing auth state")
        isLoading = true
        errorMessage = nil

        if AuthService.shared.isUserLoggedIn(), let uid = AuthService.shared.currentUserUID() {
            print("AppState: user is logged in with UID: \(uid)")
            
            // Get user from Firestore with improved error handling
            UserService.shared.fetchUser(uid: uid) { [weak self] result in
                print("AppState: fetchUser completed")
                
                DispatchQueue.main.async {
                    self?.isLoading = false

                    switch result {
                    case .success(let user):
                        print("AppState: user loaded, name: \(user.name), role: \(user.role.rawValue)")
                        self?.user = user
                        self?.isLoggedIn = true

                        // Additional debug log
                        print("AppState: user loaded, groupId = \(user.groupId ?? "none")")

                        // If user is in a group, load group information
                        if let groupId = user.groupId {
                            // Force group load
                            print("AppState: starting group load for \(groupId)")
                            GroupService.shared.fetchGroup(by: groupId)
                        }
                        
                        completion?()

                    case .failure(let error):
                        print("AppState: error loading profile: \(error.localizedDescription)")
                        self?.errorMessage = "Error loading profile: \(error.localizedDescription)"
                        self?.user = nil
                        self?.isLoggedIn = false
                        completion?()
                    }
                }
            }
        } else {
            print("AppState: user is not logged in")
            DispatchQueue.main.async {
                self.isLoading = false
                self.user = nil
                self.isLoggedIn = false
                completion?()
            }
        }
    }

    // Logout with improved error handling
    func logout() {
        print("AppState: logging out")
        isLoading = true
        
        AuthService.shared.signOut { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success:
                    print("AppState: logout successful")
                    self?.user = nil
                    self?.isLoggedIn = false
                case .failure(let error):
                    print("AppState: logout error: \(error.localizedDescription)")
                    self?.errorMessage = "Error logging out: \(error.localizedDescription)"
                }
            }
        }
    }

    // Check if user has edit permissions for module
    func hasEditPermission(for moduleId: ModuleType) -> Bool {
        guard let role = user?.role else {
            return false
        }

        // Only admins and managers can edit
        return role == .admin || role == .manager
    }

    // Check if user is a group admin
    var isGroupAdmin: Bool {
        user?.role == .admin
    }

    // Check if user has group manager rights
    var isGroupManager: Bool {
        user?.role == .admin || user?.role == .manager
    }

    // Check if user can create events
    func canCreateEvents() -> Bool {
        // Administrators and managers always can
        if isGroupManager {
            return true
        }

        // Check group settings if they allow regular members to create events
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToCreateEvents
        }

        // Default: deny
        return false
    }

    // Check if user can create setlists
    func canCreateSetlists() -> Bool {
        // Administrators and managers always can
        if isGroupManager {
            return true
        }

        // Check group settings if they allow regular members to create setlists
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToCreateSetlists
        }

        // Default: deny
        return false
    }

    // Check if user can invite other members
    func canInviteMembers() -> Bool {
        // Administrators and managers always can
        if isGroupManager {
            return true
        }

        // Check group settings if they allow regular members to invite
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToInvite
        }

        // Default: deny
        return false
    }

    // Check if user is in a group
    var isInGroup: Bool {
        user?.groupId != nil
    }

    // Проверка, ожидает ли пользователь подтверждения
    var isPendingApproval: Bool {
        guard let userId = user?.id,
              let groupId = user?.groupId else {
            return false
        }
        
        // Проверяем, загружена ли группа
        guard let group = GroupService.shared.group else {
            // Если группа еще не загружена, предполагаем что пользователь активен
            // чтобы не блокировать доступ из-за задержки загрузки
            return false
        }
        
        // Проверяем, находится ли пользователь в списке ожидания
        return group.pendingMembers.contains(userId)
    }

    // Check if user is a full member of the group
    var isActiveGroupMember: Bool {
        guard let groupId = user?.groupId,
              let userId = user?.id else {
            return false
        }

        // Если группа еще не загружена
        if GroupService.shared.group == nil {
            return false
        }

        // Проверяем, что пользователь в списке участников
        if let members = GroupService.shared.group?.members {
            return members.contains(userId)
        }

        return false
    }
}
