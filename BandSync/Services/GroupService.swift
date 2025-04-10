//
//  GroupService.swift
//  BandSync
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
        AppState.shared.$user
            .compactMap { $0?.groupId }
            .removeDuplicates()
            .sink { [weak self] groupId in
                self?.fetchGroup(by: groupId)
            }
            .store(in: &cancellables)
    }
    
    deinit {
        groupListener?.remove()
    }
    
    func fetchGroup(by id: String, completion: ((Bool) -> Void)? = nil) {
        isLoading = true
        errorMessage = nil
        
        groupListener?.remove()
        
        groupListener = db.collection("groups").document(id).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка загрузки группы: \(error.localizedDescription)"
                    completion?(false)
                    return
                }
                
                if let document = snapshot, document.exists {
                    do {
                        let group = try document.data(as: GroupModel.self)
                        self.group = group
                        self.fetchGroupMembers()
                        completion?(true)
                    } catch {
                        self.errorMessage = "Ошибка чтения данных группы"
                        completion?(false)
                    }
                } else {
                    self.errorMessage = "Группа не найдена"
                    completion?(false)
                }
            }
        }
    }
    
    func fetchGroupMembers() {
        guard let group = self.group else { return }
        
        self.groupMembers = []
        self.pendingMembers = []
        
        if group.members.isEmpty && group.pendingMembers.isEmpty { return }
        
        if !group.members.isEmpty {
            fetchUsers(userIds: group.members) { [weak self] users in
                self?.groupMembers = users
            }
        }
        
        if !group.pendingMembers.isEmpty {
            fetchUsers(userIds: group.pendingMembers) { [weak self] users in
                self?.pendingMembers = users
            }
        }
    }
    
    private func fetchUsers(userIds: [String], completion: @escaping ([UserModel]) -> Void) {
        let validUserIds = userIds.filter { !$0.isEmpty }
        if validUserIds.isEmpty { completion([]); return }
        
        db.collection("users")
            .whereField(FieldPath.documentID(), in: validUserIds)
            .getDocuments { snapshot, error in
                var users: [UserModel] = []
                
                if let documents = snapshot?.documents {
                    for doc in documents {
                        if let user = try? doc.data(as: UserModel.self) {
                            users.append(user)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    completion(users)
                }
            }
    }

    func approveUser(userId: String) {
        guard let groupId = group?.id else { return }
        
        isLoading = true
        
        let batch = db.batch()
        let groupRef = db.collection("groups").document(groupId)
        
        batch.updateData([
            "members": FieldValue.arrayUnion([userId]),
            "pendingMembers": FieldValue.arrayRemove([userId])
        ], forDocument: groupRef)
        
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                } else {
                    if let user = self?.pendingMembers.first(where: { $0.id == userId }) {
                        self?.groupMembers.append(user)
                        self?.pendingMembers.removeAll { $0.id == userId }
                        
                        if var updatedGroup = self?.group {
                            updatedGroup.members.append(userId)
                            updatedGroup.pendingMembers.removeAll { $0 == userId }
                            self?.group = updatedGroup
                        }
                    }
                    self?.objectWillChange.send()
                }
            }
        }
    }

    func rejectUser(userId: String) {
        guard let groupId = group?.id else { return }
        
        isLoading = true
        
        let batch = db.batch()
        let groupRef = db.collection("groups").document(groupId)
        let userRef = db.collection("users").document(userId)
        
        batch.updateData([
            "pendingMembers": FieldValue.arrayRemove([userId])
        ], forDocument: groupRef)
        
        batch.updateData([
            "groupId": FieldValue.delete()
        ], forDocument: userRef)
        
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                } else {
                    self?.pendingMembers.removeAll { $0.id == userId }
                    
                    if var updatedGroup = self?.group {
                        updatedGroup.pendingMembers.removeAll { $0 == userId }
                        self?.group = updatedGroup
                    }
                    self?.objectWillChange.send()
                }
            }
        }
    }

    func removeUser(userId: String, completion: ((Bool) -> Void)? = nil) {
        guard let groupId = group?.id else { completion?(false); return }
        
        // Проверяем, не удаляем ли мы последнего администратора
        let adminCount = groupMembers.filter { $0.role == .admin }.count
        let isAdminUser = groupMembers.first(where: { $0.id == userId })?.role == .admin
        let isLastAdmin = adminCount <= 1 && isAdminUser
        
        if isLastAdmin {
            errorMessage = "Невозможно удалить единственного администратора"
            completion?(false)
            return
        }
        
        isLoading = true
        
        let batch = db.batch()
        let groupRef = db.collection("groups").document(groupId)
        let userRef = db.collection("users").document(userId)
        
        batch.updateData([
            "members": FieldValue.arrayRemove([userId])
        ], forDocument: groupRef)
        
        batch.updateData([
            "groupId": FieldValue.delete(),
            "role": UserModel.UserRole.member.rawValue
        ], forDocument: userRef)
        
        batch.commit { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    self?.groupMembers.removeAll { $0.id == userId }
                    
                    if var updatedGroup = self?.group {
                        updatedGroup.members.removeAll { $0 == userId }
                        self?.group = updatedGroup
                    }
                    self?.objectWillChange.send()
                    completion?(true)
                }
            }
        }
    }

    func updateGroupName(_ newName: String, completion: ((Bool) -> Void)? = nil) {
        guard let groupId = group?.id, !newName.isEmpty else { completion?(false); return }
        
        isLoading = true
        
        db.collection("groups").document(groupId).updateData([
            "name": newName
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                    completion?(false)
                } else {
                    self?.group?.name = newName
                    self?.objectWillChange.send()
                    completion?(true)
                }
            }
        }
    }

    func regenerateCode() {
        guard let groupId = group?.id else { return }
        
        isLoading = true
        
        let newCode = UUID().uuidString.prefix(6).uppercased()
        
        db.collection("groups").document(groupId).updateData([
            "code": String(newCode)
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                } else {
                    self?.group?.code = String(newCode)
                    self?.objectWillChange.send()
                }
            }
        }
    }
    
    func changeUserRole(userId: String, newRole: UserModel.UserRole) {
        // Проверяем, не понижаем ли мы роль последнего администратора
        let adminCount = groupMembers.filter { $0.role == .admin }.count
        let isAdminUser = groupMembers.first(where: { $0.id == userId })?.role == .admin
        let isLastAdmin = adminCount <= 1 && isAdminUser && newRole != .admin
        
        if isLastAdmin {
            errorMessage = "Нужен хотя бы один администратор в группе"
            return
        }
        
        isLoading = true
        
        db.collection("users").document(userId).updateData([
            "role": newRole.rawValue
        ]) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                } else {
                    if let index = self?.groupMembers.firstIndex(where: { $0.id == userId }) {
                        self?.groupMembers[index].role = newRole
                    }
                    self?.objectWillChange.send()
                }
            }
        }
    }
    
    func createGroup(name: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let userId = AuthService.shared.currentUserUID(), !name.isEmpty else {
            let error = NSError(domain: "EmptyGroupName", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "Укажите название группы"])
            completion(.failure(error))
            return
        }
        
        isLoading = true
        
        let groupCode = UUID().uuidString.prefix(6).uppercased()
        let newGroup = GroupModel(
            name: name,
            code: String(groupCode),
            members: [userId],
            pendingMembers: [],
            createdAt: Date(),
            settings: GroupModel.GroupSettings()
        )
        
        do {
            try db.collection("groups").addDocument(from: newGroup) { [weak self] error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                        completion(.failure(error))
                    }
                    return
                }
                
                // Получаем ID созданной группы
                self?.db.collection("groups")
                    .whereField("code", isEqualTo: groupCode)
                    .getDocuments { [weak self] snapshot, error in
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            
                            if let error = error {
                                self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                                completion(.failure(error))
                                return
                            }
                            
                            guard let groupId = snapshot?.documents.first?.documentID else {
                                let error = NSError(domain: "GroupNotFound", code: -1,
                                                  userInfo: [NSLocalizedDescriptionKey: "Группа не найдена"])
                                self?.errorMessage = "Группа не найдена"
                                completion(.failure(error))
                                return
                            }
                            
                            // Обновляем пользователя
                            self?.db.collection("users").document(userId).updateData([
                                "groupId": groupId,
                                "role": "Admin"
                            ]) { error in
                                if let error = error {
                                    self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                                    completion(.failure(error))
                                } else {
                                    completion(.success(groupId))
                                }
                            }
                        }
                    }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Ошибка: \(error.localizedDescription)"
                completion(.failure(error))
            }
        }
    }

    func joinGroup(code: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = AuthService.shared.currentUserUID(), !code.isEmpty else {
            let error = NSError(domain: "EmptyGroupCode", code: -1,
                               userInfo: [NSLocalizedDescriptionKey: "Укажите код группы"])
            completion(.failure(error))
            return
        }
        
        isLoading = true
        
        db.collection("groups")
            .whereField("code", isEqualTo: code)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.isLoading = false
                        self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                        completion(.failure(error))
                        return
                    }
                    
                    guard let document = snapshot?.documents.first else {
                        self?.isLoading = false
                        self?.errorMessage = "Группа с таким кодом не найдена"
                        let error = NSError(domain: "GroupNotFound", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Группа не найдена"])
                        completion(.failure(error))
                        return
                    }
                    
                    let groupId = document.documentID
                    
                    let batch = self?.db.batch()
                    let groupRef = self?.db.collection("groups").document(groupId)
                    let userRef = self?.db.collection("users").document(userId)
                    
                    batch?.updateData([
                        "pendingMembers": FieldValue.arrayUnion([userId])
                    ], forDocument: groupRef!)
                    
                    batch?.updateData([
                        "groupId": groupId,
                        "role": UserModel.UserRole.member.rawValue
                    ], forDocument: userRef!)
                    
                    batch?.commit { error in
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            
                            if let error = error {
                                self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                                completion(.failure(error))
                            } else {
                                self?.fetchGroup(by: groupId)
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
    }
    
    func inviteUserByEmail(email: String, to groupId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isLoading = true
        
        db.collection("users")
            .whereField("email", isEqualTo: email)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.isLoading = false
                        self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                        completion(.failure(error))
                        return
                    }
                    
                    guard let userDoc = snapshot?.documents.first else {
                        self?.isLoading = false
                        self?.errorMessage = "Пользователь с таким email не найден"
                        let error = NSError(domain: "UserNotFound", code: -1,
                                          userInfo: [NSLocalizedDescriptionKey: "Пользователь не найден"])
                        completion(.failure(error))
                        return
                    }
                    
                    let userId = userDoc.documentID
                    
                    let batch = self?.db.batch()
                    let groupRef = self?.db.collection("groups").document(groupId)
                    let userRef = self?.db.collection("users").document(userId)
                    
                    batch?.updateData([
                        "pendingMembers": FieldValue.arrayUnion([userId])
                    ], forDocument: groupRef!)
                    
                    batch?.updateData([
                        "groupId": groupId,
                        "role": UserModel.UserRole.member.rawValue
                    ], forDocument: userRef!)
                    
                    batch?.commit { error in
                        DispatchQueue.main.async {
                            self?.isLoading = false
                            
                            if let error = error {
                                self?.errorMessage = "Ошибка: \(error.localizedDescription)"
                                completion(.failure(error))
                            } else {
                                self?.fetchGroup(by: groupId)
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
    }
}
