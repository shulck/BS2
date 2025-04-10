//
//  AppState.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isLoggedIn = false
    @Published var user: UserModel?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRefresh: Date = Date()

    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()

    private init() {
        print("AppState: инициализация")
        refreshAuthState()

        // Подписка на изменения состояния аутентификации Firebase
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            print("AppState: состояние аутентификации Firebase изменилось, пользователь: \(user?.uid ?? "nil")")
            self?.refreshAuthState()
        }
    }

    // Обновление состояния аутентификации с улучшенной обработкой ошибок
    func refreshAuthState(completion: (() -> Void)? = nil) {
        print("AppState: обновление состояния аутентификации")
        isLoading = true
        errorMessage = nil

        if AuthService.shared.isUserLoggedIn(), let uid = AuthService.shared.currentUserUID() {
            print("AppState: пользователь авторизован с UID: \(uid)")
            
            // Получение пользователя из Firestore
            UserService.shared.fetchUser(uid: uid) { [weak self] result in
                print("AppState: fetchUser завершен")
                
                DispatchQueue.main.async {
                    self?.isLoading = false

                    switch result {
                    case .success(let user):
                        print("AppState: пользователь загружен, имя: \(user.name), роль: \(user.role.rawValue)")
                        self?.user = user
                        self?.isLoggedIn = true
                        self?.lastRefresh = Date()

                        // Если пользователь в группе, загружаем информацию о группе
                        if let groupId = user.groupId {
                            print("AppState: загрузка группы \(groupId)")
                            GroupService.shared.fetchGroup(by: groupId)
                            
                            // Загружаем разрешения для группы
                            PermissionService.shared.fetchPermissions(for: groupId)
                        }
                        
                        completion?()

                    case .failure(let error):
                        print("AppState: ошибка загрузки профиля: \(error.localizedDescription)")
                        self?.errorMessage = "Ошибка загрузки профиля: \(error.localizedDescription)"
                        self?.user = nil
                        self?.isLoggedIn = false
                        completion?()
                    }
                }
            }
        } else {
            print("AppState: пользователь не авторизован")
            DispatchQueue.main.async {
                self.isLoading = false
                self.user = nil
                self.isLoggedIn = false
                completion?()
            }
        }
    }

    // Выход из аккаунта с улучшенной обработкой ошибок
    func logout() {
        print("AppState: выход из аккаунта")
        isLoading = true
        
        AuthService.shared.signOut { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false

                switch result {
                case .success:
                    print("AppState: выход выполнен успешно")
                    self?.user = nil
                    self?.isLoggedIn = false
                case .failure(let error):
                    print("AppState: ошибка выхода: \(error.localizedDescription)")
                    self?.errorMessage = "Ошибка выхода из аккаунта: \(error.localizedDescription)"
                    
                    // Принудительно выходим даже при ошибке
                    self?.user = nil
                    self?.isLoggedIn = false
                }
            }
        }
    }

    // Проверка наличия прав редактирования для модуля
    func hasEditPermission(for moduleId: ModuleType) -> Bool {
        guard let role = user?.role else {
            return false
        }

        // Только администраторы и менеджеры могут редактировать
        return role == .admin || role == .manager
    }

    // Проверка, является ли пользователь администратором группы
    var isGroupAdmin: Bool {
        user?.role == .admin
    }

    // Проверка наличия у пользователя прав управления группой
    var isGroupManager: Bool {
        user?.role == .admin || user?.role == .manager
    }

    // Проверка, может ли пользователь создавать события
    func canCreateEvents() -> Bool {
        // Администраторы и менеджеры всегда могут
        if isGroupManager {
            return true
        }

        // Проверка настроек группы, разрешающих обычным участникам создавать события
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToCreateEvents
        }

        // По умолчанию: запрещено
        return false
    }

    // Проверка, может ли пользователь создавать сетлисты
    func canCreateSetlists() -> Bool {
        // Администраторы и менеджеры всегда могут
        if isGroupManager {
            return true
        }

        // Проверка настроек группы, разрешающих обычным участникам создавать сетлисты
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToCreateSetlists
        }

        // По умолчанию: запрещено
        return false
    }

    // Проверка, может ли пользователь приглашать других участников
    func canInviteMembers() -> Bool {
        // Администраторы и менеджеры всегда могут
        if isGroupManager {
            return true
        }

        // Проверка настроек группы, разрешающих обычным участникам приглашать
        if let settings = GroupService.shared.group?.settings {
            return settings.allowMembersToInvite
        }

        // По умолчанию: запрещено
        return false
    }

    // Проверка, состоит ли пользователь в группе
    var isInGroup: Bool {
        user?.groupId != nil
    }

    // Проверка, ожидает ли пользователь подтверждения
    var isPendingApproval: Bool {
        guard let userId = user?.id,
              let groupId = user?.groupId else {
            return false
        }
        
        // Проверка, загружена ли группа
        if let group = GroupService.shared.group {
            // Проверка, находится ли пользователь в списке ожидания и не находится в списке участников
            return group.pendingMembers.contains(userId) && !group.members.contains(userId)
        }
        
        // Если группа еще не загружена, делаем прямой запрос
        do {
            let groupDoc = try db.collection("groups").document(groupId).getDocument().wait()
            
            if let data = groupDoc.data() {
                let pendingMembers = data["pendingMembers"] as? [String] ?? []
                let members = data["members"] as? [String] ?? []
                
                return pendingMembers.contains(userId) && !members.contains(userId)
            }
        } catch {
            print("AppState: ошибка проверки статуса ожидания: \(error.localizedDescription)")
        }
        
        // По умолчанию предполагаем, что пользователь активен
        return false
    }

    // Проверка, является ли пользователь полноправным участником группы
    var isActiveGroupMember: Bool {
        guard let userId = user?.id,
              let groupId = user?.groupId else {
            return false
        }

        // Если группа еще не загружена
        if let group = GroupService.shared.group {
            return group.members.contains(userId)
        }
        
        // Если группа еще не загружена, делаем прямой запрос
        do {
            let groupDoc = try db.collection("groups").document(groupId).getDocument().wait()
            
            if let data = groupDoc.data() {
                let members = data["members"] as? [String] ?? []
                return members.contains(userId)
            }
        } catch {
            print("AppState: ошибка проверки активного членства: \(error.localizedDescription)")
        }

        return false
    }
    
    // Получение статуса пользователя (для отображения в UI)
    var userStatus: UserStatus {
        if !isLoggedIn {
            return .notLoggedIn
        }
        
        if user?.groupId == nil {
            return .noGroup
        }
        
        if isPendingApproval {
            return .pendingApproval
        }
        
        return .active
    }
    
    // Перечисление возможных статусов пользователя
    enum UserStatus {
        case notLoggedIn
        case noGroup
        case pendingApproval
        case active
    }
}

// Расширение для FirestoreDocument для синхронного получения документа (только для внутреннего использования)
extension DocumentReference {
    func getDocument() -> DocumentSnapshotTask {
        return DocumentSnapshotTask(reference: self)
    }
}

// Вспомогательный класс для имитации синхронного получения документа
class DocumentSnapshotTask {
    private let reference: DocumentReference
    private var snapshot: DocumentSnapshot?
    private var error: Error?
    
    init(reference: DocumentReference) {
        self.reference = reference
    }
    
    func wait() throws -> DocumentSnapshot {
        let semaphore = DispatchSemaphore(value: 0)
        
        reference.getDocument { snapshot, error in
            self.snapshot = snapshot
            self.error = error
            semaphore.signal()
        }
        
        // Ожидаем завершения запроса (с таймаутом)
        let result = semaphore.wait(timeout: .now() + 5)
        
        if result == .timedOut {
            throw NSError(domain: "AppState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for document"])
        }
        
        if let error = error {
            throw error
        }
        
        if let snapshot = snapshot, snapshot.exists {
            return snapshot
        }
        
        throw NSError(domain: "AppState", code: -1, userInfo: [NSLocalizedDescriptionKey: "Document not found"])
    }
}
