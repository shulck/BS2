//
//  GroupService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 09.04.2025.
//

import Foundation
import FirebaseFirestore
import Combine

final class GroupService: ObservableObject {
    static let shared = GroupService()

    @Published var group: GroupModel?
    @Published var groupMembers: [UserModel] = []
    @Published var pendingMembers: [UserModel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var groupListener: ListenerRegistration?
    
    init() {
        print("GroupService: initialized")
        // Setup subscription to user changes
        AppState.shared.$user
            .compactMap { $0?.groupId }
            .removeDuplicates()
            .sink { [weak self] groupId in
                print("GroupService: User's groupId changed to: \(groupId)")
                self?.fetchGroup(by: groupId)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        groupListener?.remove()
        print("GroupService: listener removed")
    }
    
    // Get group information by ID with improved error handling
    func fetchGroup(by id: String, completion: ((Bool) -> Void)? = nil) {
        isLoading = true
        errorMessage = nil
        
        print("GroupService: fetching group with ID: \(id)")
        
        // Remove previous listener if exists
        groupListener?.remove()
        
        // Create new listener to track group changes
        groupListener = db.collection("groups").document(id).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("GroupService: error loading group: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Error loading group: \(error.localizedDescription)"
                    self.isLoading = false
                    completion?(false)
                }
                return
            }
            
            if let document = snapshot, document.exists {
                print("GroupService: group document exists, attempting to decode")
                do {
                    let group = try document.data(as: GroupModel.self)
                    print("GroupService: group successfully decoded: \(group.name)")
                    DispatchQueue.main.async {
                        self.group = group
                        self.isLoading = false
                        self.fetchGroupMembers()
                        completion?(true)
                    }
                } catch {
                    print("GroupService: error converting group data: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Error converting group data: \(error.localizedDescription)"
                        self.isLoading = false
                        
                        // Try to recover data manually
                        if let data = document.data() {
                            print("GroupService: attempting manual data recovery")
                            self.createGroupFromData(id: id, data: data)
                            completion?(true)
                        } else {
                            completion?(false)
                        }
                    }
                }
            } else {
                print("GroupService: group not found")
                DispatchQueue.main.async {
                    self.errorMessage = "Group not found"
                    self.isLoading = false
                    completion?(false)
                    
                    // If group not found, clear the groupId from user
                    if let userId = AppState.shared.user?.id {
                        print("GroupService: clearing groupId for user: \(userId)")
                        self.db.collection("users").document(userId).updateData([
                            "groupId": FieldValue.delete()
                        ]) { error in
                            if let error = error {
                                print("GroupService: error clearing groupId: \(error.localizedDescription)")
                            } else {
                                print("GroupService: groupId cleared successfully")
                                // Refresh app state
                                AppState.shared.refreshAuthState()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Direct fetch of group (no listener) with completion
    func directFetchGroup(by id: String, completion: @escaping (Result<GroupModel, Error>) -> Void) {
        print("GroupService: direct fetch of group: \(id)")
        
        db.collection("groups").document(id).getDocument { snapshot, error in
            if let error = error {
                print("GroupService: direct fetch error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            if let document = snapshot, document.exists {
                do {
                    let group = try document.data(as: GroupModel.self)
                    print("GroupService: direct fetch successful")
                    completion(.success(group))
                } catch {
                    print("GroupService: direct fetch decoding error: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            } else {
                let error = NSError(domain: "GroupService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Group not found"])
                print("GroupService: direct fetch - group not found")
                completion(.failure(error))
            }
        }
    }
    
    // Manual creation of group model from data
    private func createGroupFromData(id: String, data: [String: Any]) {
        print("GroupService: manual group creation from data")
        
        guard let name = data["name"] as? String,
              let code = data["code"] as? String else {
            self.errorMessage = "Missing required group fields"
            return
        }
        
        let members = data["members"] as? [String] ?? []
        let pendingMembers = data["pendingMembers"] as? [String] ?? []
        let createdAtTimestamp = data["createdAt"] as? Timestamp
        let createdAt = createdAtTimestamp?.dateValue()
        
        let settingsData = data["settings"] as? [String: Any]
        let settings = createSettingsFromData(settingsData)
        
        let group = GroupModel(
            id: id,
            name: name,
            code: code,
            members: members,
            pendingMembers: pendingMembers,
            createdAt: createdAt,
            settings: settings
        )
        
        print("GroupService: manual group created: \(name)")
        self.group = group
        self.fetchGroupMembers()
    }
    
    // Manual creation of settings from data
    private func createSettingsFromData(_ data: [String: Any]?) -> GroupModel.GroupSettings {
        var allowMembersToInvite = true
        var allowMembersToCreateEvents = true
        var allowMembersToCreateSetlists = true
        var allowGuestAccess = false
        var enableNotifications = true
        var enabledModules = ModuleType.allCases.map { $0.rawValue }
        
        if let data = data {
            if let value = data["allowMembersToInvite"] as? Bool {
                allowMembersToInvite = value
            }
            
            if let value = data["allowMembersToCreateEvents"] as? Bool {
                allowMembersToCreateEvents = value
            }
            
            if let value = data["allowMembersToCreateSetlists"] as? Bool {
                allowMembersToCreateSetlists = value
            }
            
            if let value = data["allowGuestAccess"] as? Bool {
                allowGuestAccess = value
            }
            
            if let value = data["enableNotifications"] as? Bool {
                enableNotifications = value
            }
            
            if let moduleSettingsData = data["moduleSettings"] as? [String: Any],
               let modules = moduleSettingsData["enabledModules"] as? [String] {
                enabledModules = modules
            }
        }

        // Create settings with obtained values
        let settings = GroupModel.GroupSettings(
            allowMembersToInvite: allowMembersToInvite,
            allowMembersToCreateEvents: allowMembersToCreateEvents,
            allowMembersToCreateSetlists: allowMembersToCreateSetlists,
            allowGuestAccess: allowGuestAccess,
            enableNotifications: enableNotifications,
            moduleSettings: GroupModel.GroupSettings.ModuleSettings(enabledModules: enabledModules)
        )
        
        return settings
    }

    // Get information about group users with improved error handling
    func fetchGroupMembers() {
        guard let group = self.group else {
            print("GroupService: cannot fetch members, group is nil")
            return
        }
        
        // Clear existing data
        self.groupMembers = []
        self.pendingMembers = []
        
        // Handle empty lists
        if group.members.isEmpty && group.pendingMembers.isEmpty {
            print("GroupService: group has no members or pending members")
            return
        }
        
        isLoading = true
        
        // Get active members
        if !group.members.isEmpty {
            print("GroupService: fetching \(group.members.count) active members")
            fetchUserBatch(userIds: group.members, isActive: true)
        }
        
        // Get pending members
        if !group.pendingMembers.isEmpty {
            print("GroupService: fetching \(group.pendingMembers.count) pending members")
            fetchUserBatch(userIds: group.pendingMembers, isActive: false)
        }
    }
    
    // Улучшенная функция загрузки пользователей с фиксированной обработкой результатов
    private func fetchUserBatch(userIds: [String], isActive: Bool) {
        // Фильтруем валидные ID пользователей
        let validUserIds = userIds.filter { !$0.isEmpty }
        guard !validUserIds.isEmpty else {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            return
        }
        
        // Очищаем соответствующий массив перед загрузкой новых пользователей
        if isActive {
            self.groupMembers = []
        } else {
            self.pendingMembers = []
        }
        
        print("GroupService: начинаем загрузку \(validUserIds.count) пользователей (isActive: \(isActive))")
        print("GroupService: ID пользователей для загрузки: \(validUserIds)")
        
        let batchSize = 10
        var remainingIds = validUserIds
        
        // Function to process next batch
        func processNextBatch() {
            guard !remainingIds.isEmpty else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    print("GroupService: загрузка завершена, активных: \(self.groupMembers.count), ожидающих: \(self.pendingMembers.count)")
                    // Явно сообщаем о изменении объекта для обновления UI
                    self.objectWillChange.send()
                }
                return
            }
            
            let currentBatch = Array(remainingIds.prefix(batchSize))
            remainingIds = Array(remainingIds.dropFirst(min(batchSize, remainingIds.count)))
            
            print("GroupService: processing batch of \(currentBatch.count) users")
            
            db.collection("users")
                .whereField(FieldPath.documentID(), in: currentBatch)
                .getDocuments { [weak self] snapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("GroupService: error loading users: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.errorMessage = "Error loading users: \(error.localizedDescription)"
                            
                            // Continue with next batch even with error
                            processNextBatch()
                        }
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        print("GroupService: no user documents found")
                        DispatchQueue.main.async {
                            processNextBatch()
                        }
                        return
                    }
                    
                    // Process obtained documents
                    let users = documents.compactMap { doc -> UserModel? in
                        do {
                            // Try to decode as model
                            let user = try doc.data(as: UserModel.self)
                            print("GroupService: successfully decoded user: \(user.name), id: \(user.id ?? "nil")")
                            return user
                        } catch {
                            print("GroupService: error decoding user: \(error.localizedDescription)")
                            
                            // If failed, assemble manually
                            let data = doc.data()
                            let id = doc.documentID
                            if let email = data["email"] as? String {
                                let name = data["name"] as? String ?? "Unknown User"
                                let phone = data["phone"] as? String ?? ""
                                let groupId = data["groupId"] as? String
                                let roleString = data["role"] as? String ?? "Member"
                                let role = UserModel.UserRole(rawValue: roleString) ?? .member
                                
                                print("GroupService: manually created user: \(name), id: \(id)")
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
                    
                    DispatchQueue.main.async {
                        // Add users to appropriate arrays
                        if isActive {
                            self.groupMembers.append(contentsOf: users)
                            print("GroupService: добавлено \(users.count) активных пользователей, всего: \(self.groupMembers.count)")
                        } else {
                            self.pendingMembers.append(contentsOf: users)
                            print("GroupService: добавлено \(users.count) ожидающих пользователей, всего: \(self.pendingMembers.count)")
                        }
                        
                        // Process next batch
                        processNextBatch()
                    }
                }
        }
        
        // Launch first batch
        processNextBatch()
    }

    // Approve user (move from pending to active members)
    func approveUser(userId: String) {
        guard let groupId = group?.id else {
            print("GroupService: cannot approve user, group ID is nil")
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: approving user: \(userId)")
        
        // Create transaction for safe user movement
        db.runTransaction({ [weak self] (transaction, errorPointer) -> Any? in
            let groupRef = self?.db.collection("groups").document(groupId)
            
            guard let document = try? transaction.getDocument(groupRef!),
                  let data = document.data() else {
                print("GroupService: transaction failed - cannot get group document")
                return nil
            }
            
            // Get member arrays
            var members = data["members"] as? [String] ?? []
            var pendingMembers = data["pendingMembers"] as? [String] ?? []
            
            // Check if user is in pending list
            guard pendingMembers.contains(userId) else {
                print("GroupService: user not found in pending members")
                return nil
            }
            
            // Remove user from pending list
            pendingMembers.removeAll { $0 == userId }
            
            // Add user to members list (if not already there)
            if !members.contains(userId) {
                members.append(userId)
            }
            
            // Update group
            if let groupRef = groupRef {
                transaction.updateData([
                    "members": members,
                    "pendingMembers": pendingMembers
                ], forDocument: groupRef)
            }
            
            return [members, pendingMembers]
        }) { [weak self] (result, error) in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error approving user: \(error.localizedDescription)")
                    self?.errorMessage = "Error approving user: \(error.localizedDescription)"
                } else {
                    print("GroupService: user approved successfully")
                    self?.successMessage = "User approved successfully"
                    
                    // Update local data
                    if let pendingIndex = self?.pendingMembers.firstIndex(where: { $0.id == userId }) {
                        if let user = self?.pendingMembers[pendingIndex] {
                            self?.groupMembers.append(user)
                            self?.pendingMembers.remove(at: pendingIndex)
                            
                            // Update local group model
                            if var updatedGroup = self?.group {
                                updatedGroup.members.append(userId)
                                updatedGroup.pendingMembers.removeAll { $0 == userId }
                                self?.group = updatedGroup
                            }
                        }
                    }
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                }
            }
        }
    }

    // Reject user application
    func rejectUser(userId: String) {
        guard let groupId = group?.id else {
            print("GroupService: cannot reject user, group ID is nil")
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: rejecting user: \(userId)")
        
        // Create batch update
        let batch = db.batch()
        
        // Remove user from pending list in group
        let groupRef = db.collection("groups").document(groupId)
        batch.updateData([
            "pendingMembers": FieldValue.arrayRemove([userId])
        ], forDocument: groupRef)
        
        // Clear groupId in user profile
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "groupId": FieldValue.delete()
        ], forDocument: userRef)
        
        // Execute batch update
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error rejecting application: \(error.localizedDescription)")
                    self?.errorMessage = "Error rejecting application: \(error.localizedDescription)"
                } else {
                    print("GroupService: application rejected")
                    self?.successMessage = "Application rejected"
                    
                    // Update local data
                    if let pendingIndex = self?.pendingMembers.firstIndex(where: { $0.id == userId }) {
                        self?.pendingMembers.remove(at: pendingIndex)
                    }
                    
                    // Update local group model
                    if var updatedGroup = self?.group {
                        updatedGroup.pendingMembers.removeAll { $0 == userId }
                        self?.group = updatedGroup
                    }
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                }
            }
        }
    }

    // Remove user from group
    func removeUser(userId: String, completion: ((Bool) -> Void)? = nil) {
        guard let groupId = group?.id else {
            print("GroupService: cannot remove user, group ID is nil")
            completion?(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: removing user: \(userId)")
        
        // Check if we're not removing the last admin
        let isLastAdmin = groupMembers.filter { $0.role == .admin }.count <= 1 &&
                          groupMembers.first(where: { $0.id == userId })?.role == .admin
        
        if isLastAdmin {
            print("GroupService: cannot remove the last admin")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Cannot remove the only administrator of the group"
                completion?(false)
            }
            return
        }
        
        // Create batch update
        let batch = db.batch()
        
        // Remove user from members list
        let groupRef = db.collection("groups").document(groupId)
        batch.updateData([
            "members": FieldValue.arrayRemove([userId])
        ], forDocument: groupRef)
        
        // Clear groupId in user profile
        let userRef = db.collection("users").document(userId)
        batch.updateData([
            "groupId": FieldValue.delete(),
            "role": UserModel.UserRole.member.rawValue // Reset role to member
        ], forDocument: userRef)
        
        // Execute batch update
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error removing user: \(error.localizedDescription)")
                    self?.errorMessage = "Error removing user: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    print("GroupService: user removed from group")
                    self?.successMessage = "User removed from group"
                    
                    // Update local data
                    if let memberIndex = self?.groupMembers.firstIndex(where: { $0.id == userId }) {
                        self?.groupMembers.remove(at: memberIndex)
                    }
                    
                    // Update local group model
                    if var updatedGroup = self?.group {
                        updatedGroup.members.removeAll { $0 == userId }
                        self?.group = updatedGroup
                    }
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                    
                    completion?(true)
                }
            }
        }
    }

    // Update group name
    func updateGroupName(_ newName: String, completion: ((Bool) -> Void)? = nil) {
        guard let groupId = group?.id, !newName.isEmpty else {
            print("GroupService: cannot update group name, invalid parameters")
            completion?(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: updating group name to: \(newName)")
        
        db.collection("groups").document(groupId).updateData([
            "name": newName
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error updating name: \(error.localizedDescription)")
                    self?.errorMessage = "Error updating name: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    print("GroupService: group name updated")
                    self?.successMessage = "Group name updated"
                    
                    // Update local data
                    self?.group?.name = newName
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                    
                    completion?(true)
                }
            }
        }
    }

    // Generate new invitation code
    func regenerateCode() {
        guard let groupId = group?.id else {
            print("GroupService: cannot regenerate code, group ID is nil")
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: regenerating invitation code")
        
        let newCode = UUID().uuidString.prefix(6).uppercased()

        db.collection("groups").document(groupId).updateData([
            "code": String(newCode)
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error updating code: \(error.localizedDescription)")
                    self?.errorMessage = "Error updating code: \(error.localizedDescription)"
                } else {
                    print("GroupService: new invitation code created")
                    self?.successMessage = "New invitation code created"
                    
                    // Update local data
                    self?.group?.code = String(newCode)
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                }
            }
        }
    }
    
    // Change user role
    func changeUserRole(userId: String, newRole: UserModel.UserRole) {
        guard let currentUserId = AppState.shared.user?.id, userId != currentUserId || newRole == .admin else {
            // Cannot downgrade yourself unless you remain admin
            print("GroupService: cannot change own role")
            errorMessage = "Cannot change your own role"
            return
        }
        
        // Check if we're not removing the last admin
        let isLastAdmin = groupMembers.filter { $0.role == .admin }.count <= 1 &&
                          groupMembers.first(where: { $0.id == userId })?.role == .admin &&
                          newRole != .admin
        
        if isLastAdmin {
            print("GroupService: cannot remove the last admin")
            errorMessage = "Need to have at least one administrator in the group"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: changing role for user \(userId) to \(newRole.rawValue)")
        
        db.collection("users").document(userId).updateData([
            "role": newRole.rawValue
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("GroupService: error changing role: \(error.localizedDescription)")
                    self?.errorMessage = "Error changing role: \(error.localizedDescription)"
                } else {
                    print("GroupService: user role changed")
                    self?.successMessage = "User role changed"
                    
                    // Update local data
                    if let memberIndex = self?.groupMembers.firstIndex(where: { $0.id == userId }) {
                        var updatedUser = self?.groupMembers[memberIndex]
                        updatedUser?.role = newRole
                        
                        if let user = updatedUser {
                            self?.groupMembers[memberIndex] = user
                        }
                    }
                    
                    // Принудительно отправляем сигнал обновления UI
                    self?.objectWillChange.send()
                    
                    // Обновляем информацию о группе, чтобы отразить изменения
                    if let groupId = self?.group?.id {
                        self?.fetchGroup(by: groupId)
                    }
                }
            }
        }
    }
    
    // Create new group с проверкой уникальности кода
    func createGroup(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userId = AuthService.shared.currentUserUID(), !name.isEmpty else {
            print("GroupService: cannot create group, invalid parameters")
            let error = NSError(domain: "EmptyGroupName", code: -1, userInfo: [NSLocalizedDescriptionKey: "You must specify a group name"])
            completion(.failure(error))
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: creating new group: \(name)")
        
        // Генерируем код и проверяем его уникальность
        generateUniqueGroupCode { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let groupCode):
                print("GroupService: generated unique code: \(groupCode)")
                self.continueGroupCreation(name: name, userId: userId, groupCode: groupCode, completion: completion)
                
            case .failure(let error):
                print("GroupService: error generating unique code: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error generating group code: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Генерация уникального кода группы
    private func generateUniqueGroupCode(attempts: Int = 0, completion: @escaping (Result<String, Error>) -> Void) {
        // Ограничиваем количество попыток
        guard attempts < 5 else {
            let error = NSError(domain: "GroupCodeGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate unique group code after multiple attempts"])
            completion(.failure(error))
            return
        }
        
        let groupCode = UUID().uuidString.prefix(6).uppercased()
        
        // Проверяем, существует ли уже такой код
        db.collection("groups")
            .whereField("code", isEqualTo: String(groupCode))
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                if let documents = snapshot?.documents, !documents.isEmpty {
                    // Код уже существует, генерируем новый и повторяем
                    print("GroupService: generated code already exists, regenerating (attempt \(attempts + 1))")
                    self?.generateUniqueGroupCode(attempts: attempts + 1, completion: completion)
                    return
                }
                
                // Код уникален
                completion(.success(String(groupCode)))
            }
    }
    
    // Продолжаем создание группы с уникальным кодом
    private func continueGroupCreation(name: String, userId: String, groupCode: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Create default settings
        let settings = GroupModel.GroupSettings()
        
        let newGroup = GroupModel(
            name: name,
            code: groupCode,
            members: [userId],
            pendingMembers: [],
            createdAt: Date(),
            settings: settings
        )
        
        do {
            try db.collection("groups").addDocument(from: newGroup) { [weak self] error in
                guard let self = self else { return }
                
                if let error = error {
                    print("GroupService: error creating group: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Error creating group: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                    return
                }
                
                print("GroupService: group created successfully")
                self.successMessage = "Group successfully created!"
                
                // Get ID of created group
                self.db.collection("groups")
                    .whereField("code", isEqualTo: groupCode)
                    .getDocuments { [weak self] snapshot, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("GroupService: error getting group ID: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.isLoading = false
                                self.errorMessage = "Error getting group ID: \(error.localizedDescription)"
                                completion(.failure(error))
                            }
                            return
                        }
                        
                        if let groupId = snapshot?.documents.first?.documentID {
                            print("GroupService: group ID found: \(groupId)")
                            
                            // Batch update: assign groupId to user and set admin role
                            let batch = self.db.batch()
                            let userRef = self.db.collection("users").document(userId)
                            
                            batch.updateData([
                                "groupId": groupId,
                                "role": "Admin"
                            ], forDocument: userRef)
                            
                            batch.commit { error in
                                DispatchQueue.main.async {
                                    self.isLoading = false
                                    
                                    if let error = error {
                                        print("GroupService: error updating user: \(error.localizedDescription)")
                                        self.errorMessage = "Error updating user: \(error.localizedDescription)"
                                        completion(.failure(error))
                                    } else {
                                        print("GroupService: user updated as admin")
                                        completion(.success(groupId))
                                    }
                                }
                            }
                        } else {
                            print("GroupService: created group not found")
                            DispatchQueue.main.async {
                                self.isLoading = false
                                self.errorMessage = "Could not find created group"
                                let error = NSError(domain: "GroupNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not find created group"])
                                completion(.failure(error))
                            }
                        }
                    }
            }
        } catch {
            print("GroupService: error serializing group: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Error creating group: \(error.localizedDescription)"
                completion(.failure(error))
            }
        }
    }

    // Join existing group by code
    func joinGroup(code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = AuthService.shared.currentUserUID(), !code.isEmpty else {
            print("GroupService: cannot join group, invalid parameters")
            let error = NSError(domain: "EmptyGroupCode", code: -1, userInfo: [NSLocalizedDescriptionKey: "You must specify a group code"])
            completion(.failure(error))
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        print("GroupService: joining group with code: \(code)")
        
        db.collection("groups")
            .whereField("code", isEqualTo: code)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("GroupService: error searching for group: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Error searching for group: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    print("GroupService: group with this code not found")
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "Group with this code not found"
                        let error = NSError(domain: "GroupNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "Group with this code not found"])
                        completion(.failure(error))
                    }
                    return
                }
                
                let groupId = document.documentID
                print("GroupService: found group: \(groupId)")
                
                // Проверяем, уже находится ли пользователь в группе или ожидает подтверждения
                do {
                    let group = try document.data(as: GroupModel.self)
                    
                    // Проверка, находится ли пользователь уже в группе
                    if group.members.contains(userId) {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.errorMessage = "You are already a member of this group"
                            let error = NSError(domain: "AlreadyMember", code: -1, userInfo: [NSLocalizedDescriptionKey: "You are already a member of this group"])
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    // Проверка, находится ли пользователь уже в списке ожидания
                    if group.pendingMembers.contains(userId) {
                        DispatchQueue.main.async {
                            self.isLoading = false
                            self.errorMessage = "Your request is already pending approval"
                            let error = NSError(domain: "AlreadyPending", code: -1, userInfo: [NSLocalizedDescriptionKey: "Your request is already pending approval"])
                            completion(.failure(error))
                        }
                        return
                    }
                } catch {
                    print("GroupService: error decoding group: \(error.localizedDescription)")
                    // Продолжаем обработку, даже если не удалось декодировать группу
                }
                
                // Batch update: add user to pendingMembers and update user profile
                let batch = self.db.batch()
                
                // Update group - всегда добавляем в pendingMembers, никогда в members
                let groupRef = self.db.collection("groups").document(groupId)
                batch.updateData([
                    "pendingMembers": FieldValue.arrayUnion([userId])
                ], forDocument: groupRef)
                
                // Update user - устанавливаем groupId но с ограниченным доступом
                let userRef = self.db.collection("users").document(userId)
                batch.updateData([
                    "groupId": groupId,
                    "role": UserModel.UserRole.member.rawValue // Устанавливаем роль как обычный участник
                ], forDocument: userRef)
                
                batch.commit { error in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        if let error = error {
                            print("GroupService: error joining group: \(error.localizedDescription)")
                            self.errorMessage = "Error joining group: \(error.localizedDescription)"
                            completion(.failure(error))
                        } else {
                            print("GroupService: join request sent successfully")
                            self.successMessage = "Join request sent. Waiting for approval."
                            
                            // Обновляем локальные данные
                            self.fetchGroup(by: groupId)
                            
                            // Принудительно отправляем сигнал обновления UI
                            self.objectWillChange.send()
                            
                            completion(.success(()))
                        }
                    }
                }
            }
    }
    
    // Check if user is admin
    func isUserAdmin(userId: String) -> Bool {
        return groupMembers.first(where: { $0.id == userId })?.role == .admin
    }
    
    // Check if user is group member
    func isUserMember(userId: String) -> Bool {
        return group?.members.contains(userId) == true
    }
    
    // Method to invite user by email
    func inviteUserByEmail(email: String, to groupId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Find user by email
        print("GroupService: inviting user with email: \(email) to group: \(groupId)")
        
        UserService.shared.findUserByEmail(email) { [weak self] result in
            switch result {
            case .success(let user):
                if let user = user {
                    print("GroupService: user found: \(user.name)")
                    // User found, add to pending members
                    let batch = self?.db.batch()
                    
                    // Update group
                    let groupRef = self?.db.collection("groups").document(groupId)
                    batch?.updateData([
                        "pendingMembers": FieldValue.arrayUnion([user.id ?? ""])
                    ], forDocument: groupRef!)
                    
                    // Update user
                    let userRef = self?.db.collection("users").document(user.id ?? "")
                    batch?.updateData([
                        "groupId": groupId
                    ], forDocument: userRef!)
                    
                    batch?.commit { error in
                        if let error = error {
                            print("GroupService: error inviting user: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("GroupService: user invited successfully")
                            
                            // Принудительно отправляем сигнал обновления UI
                            DispatchQueue.main.async {
                                self?.objectWillChange.send()
                            }
                            
                            completion(.success(()))
                        }
                    }
                } else {
                    // User not found
                    print("GroupService: user not found with email: \(email)")
                    let error = NSError(domain: "UserNotFound", code: -1, userInfo: [NSLocalizedDescriptionKey: "User with this email not found"])
                    completion(.failure(error))
                }
            case .failure(let error):
                print("GroupService: error finding user: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}
