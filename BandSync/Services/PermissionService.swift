//
//  PermissionService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import Foundation
import FirebaseFirestore
import Combine

final class PermissionService: ObservableObject {
    static let shared = PermissionService()
    
    @Published var permissions: PermissionModel?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    private var permissionsListener: ListenerRegistration?
    
    init() {
        // Автоматическая проверка разрешений при изменении пользователя
        AppState.shared.$user
            .removeDuplicates()
            .sink { [weak self] user in
                if let groupId = user?.groupId {
                    self?.fetchPermissions(for: groupId)
                } else {
                    self?.permissions = nil
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        permissionsListener?.remove()
    }
    
    // Получение разрешений для группы
    func fetchPermissions(for groupId: String) {
        isLoading = true
        
        // Удаляем предыдущий listener, если он есть
        permissionsListener?.remove()
        
        // Создаем новый listener для отслеживания изменений в правах доступа
        permissionsListener = db.collection("permissions")
            .whereField("groupId", isEqualTo: groupId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка загрузки разрешений: \(error.localizedDescription)"
                    return
                }
                
                if let document = snapshot?.documents.first {
                    do {
                        let permissionModel = try document.data(as: PermissionModel.self)
                        DispatchQueue.main.async {
                            self.permissions = permissionModel
                            self.objectWillChange.send()
                        }
                    } catch {
                        self.errorMessage = "Ошибка чтения данных о разрешениях"
                        
                        // Пробуем создать объект вручную
                        let data = document.data()
                        self.createPermissionsFromData(document.documentID, data: data, groupId: groupId)
                    }
                } else {
                    // Если нет разрешений для группы, создаем значения по умолчанию
                    self.createDefaultPermissions(for: groupId)
                }
            }
    }
    
    // Ручное создание разрешений из данных
    private func createPermissionsFromData(_ documentId: String, data: [String: Any], groupId: String) {
        if let modulesData = data["modules"] as? [[String: Any]] {
            var modules: [PermissionModel.ModulePermission] = []
            
            for moduleData in modulesData {
                if let moduleIdString = moduleData["moduleId"] as? String,
                   let moduleId = ModuleType(rawValue: moduleIdString),
                   let roleAccessStrings = moduleData["roleAccess"] as? [String] {
                    
                    let roles = roleAccessStrings.compactMap { UserModel.UserRole(rawValue: $0) }
                    let module = PermissionModel.ModulePermission(moduleId: moduleId, roleAccess: roles)
                    modules.append(module)
                }
            }
            
            // Добавляем недостающие модули с разрешениями по умолчанию
            let existingModuleIds = modules.map { $0.moduleId }
            for moduleType in ModuleType.allCases {
                if !existingModuleIds.contains(moduleType) {
                    // Добавляем разрешения по умолчанию
                    let defaultRoles: [UserModel.UserRole]
                    switch moduleType {
                    case .admin:
                        defaultRoles = [.admin]
                    case .finances, .merchandise, .contacts:
                        defaultRoles = [.admin, .manager]
                    case .calendar, .setlists, .tasks, .chats:
                        defaultRoles = [.admin, .manager, .musician, .member]
                    }
                    modules.append(PermissionModel.ModulePermission(moduleId: moduleType, roleAccess: defaultRoles))
                }
            }
            
            let permissionModel = PermissionModel(id: documentId, groupId: groupId, modules: modules)
            
            DispatchQueue.main.async {
                self.permissions = permissionModel
                self.objectWillChange.send()
            }
        }
    }
    
    // Создание разрешений по умолчанию для новой группы
    func createDefaultPermissions(for groupId: String) {
        isLoading = true
        
        // Разрешения по умолчанию для всех модулей
        let defaultModules: [PermissionModel.ModulePermission] = ModuleType.allCases.map { moduleType in
            // По умолчанию, администраторы и менеджеры имеют доступ ко всему
            // Обычные участники - только к календарю, сетлистам, задачам и чатам
            let roles: [UserModel.UserRole]
            
            switch moduleType {
            case .admin:
                // К админке доступ только у админов
                roles = [.admin]
            case .finances, .merchandise, .contacts:
                // Финансы, мерч и контакты требуют прав менеджера
                roles = [.admin, .manager]
            case .calendar, .setlists, .tasks, .chats:
                // Базовые модули доступны всем
                roles = [.admin, .manager, .musician, .member]
            }
            
            return PermissionModel.ModulePermission(moduleId: moduleType, roleAccess: roles)
        }
        
        let newPermissions = PermissionModel(groupId: groupId, modules: defaultModules)
        
        do {
            _ = try db.collection("permissions").addDocument(from: newPermissions) { [weak self] error in
                guard let self = self else { return }
                
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка создания разрешений: \(error.localizedDescription)"
                } else {
                    // Загружаем созданные разрешения
                    self.fetchPermissions(for: groupId)
                }
            }
        } catch {
            isLoading = false
            errorMessage = "Ошибка обработки данных о разрешениях: \(error.localizedDescription)"
        }
    }
    
    // Обновление разрешений для модуля
    func updateModulePermission(moduleId: ModuleType, roles: [UserModel.UserRole]) {
        guard let permissionId = permissions?.id else {
            errorMessage = "Отсутствует ID разрешений"
            return
        }
        
        isLoading = true
        
        if var modules = permissions?.modules {
            if let index = modules.firstIndex(where: { $0.moduleId == moduleId }) {
                modules[index] = PermissionModel.ModulePermission(moduleId: moduleId, roleAccess: roles)
                
                db.collection("permissions").document(permissionId).updateData([
                    "modules": modules.map { [
                        "moduleId": $0.moduleId.rawValue,
                        "roleAccess": $0.roleAccess.map { $0.rawValue }
                    ]}
                ]) { [weak self] error in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        if let error = error {
                            self.errorMessage = "Ошибка обновления разрешений: \(error.localizedDescription)"
                        } else {
                            // Обновляем локальные данные
                            self.permissions?.modules = modules
                            
                            // Принудительно обновляем UI
                            self.objectWillChange.send()
                        }
                    }
                }
            } else {
                // Модуль не найден, добавляем его
                let newModule = PermissionModel.ModulePermission(moduleId: moduleId, roleAccess: roles)
                modules.append(newModule)
                
                db.collection("permissions").document(permissionId).updateData([
                    "modules": modules.map { [
                        "moduleId": $0.moduleId.rawValue,
                        "roleAccess": $0.roleAccess.map { $0.rawValue }
                    ]}
                ]) { [weak self] error in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        self.isLoading = false
                        
                        if let error = error {
                            self.errorMessage = "Ошибка добавления нового модуля: \(error.localizedDescription)"
                        } else {
                            self.permissions?.modules = modules
                            
                            // Принудительно обновляем UI
                            self.objectWillChange.send()
                        }
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Нет модулей в текущих разрешениях"
            }
        }
    }
    
    // Проверка, имеет ли пользователь доступ к модулю
    func hasAccess(to moduleId: ModuleType, role: UserModel.UserRole) -> Bool {
        // Администраторы всегда имеют доступ ко всему
        if role == .admin {
            return true
        }
        
        // Если разрешения еще не загружены, используем безопасные значения по умолчанию
        if permissions == nil {
            switch moduleId {
            case .admin:
                return role == .admin
            case .finances, .merchandise, .contacts:
                return role == .admin || role == .manager
            case .calendar, .setlists, .tasks, .chats:
                return true // Базовые модули доступны всем по умолчанию
            }
        }
        
        // Проверяем разрешения из базы данных
        if let modulePermission = permissions?.modules.first(where: { $0.moduleId == moduleId }) {
            return modulePermission.hasAccess(role: role)
        }
        
        // Если модуль не найден в разрешениях, используем значения по умолчанию
        switch moduleId {
        case .admin:
            return role == .admin
        case .finances, .merchandise, .contacts:
            return role == .admin || role == .manager
        case .calendar, .setlists, .tasks, .chats:
            return true // Базовые модули доступны всем по умолчанию
        }
    }
    
    // Проверка доступа для текущего пользователя
    func currentUserHasAccess(to moduleId: ModuleType) -> Bool {
        guard let userRole = AppState.shared.user?.role else {
            return false
        }
        
        return hasAccess(to: moduleId, role: userRole)
    }
    
    // Получение всех модулей, к которым у пользователя есть доступ
    func getAccessibleModules(for role: UserModel.UserRole) -> [ModuleType] {
        // Администраторы имеют доступ ко всему
        if role == .admin {
            return ModuleType.allCases
        }
        
        // Если разрешения еще не загружены, используем значения по умолчанию
        if permissions == nil {
            var accessibleModules: [ModuleType] = []
            
            // Базовые модули для всех пользователей
            accessibleModules.append(contentsOf: [.calendar, .setlists, .tasks, .chats])
            
            // Дополнительные модули для менеджеров
            if role == .manager {
                accessibleModules.append(contentsOf: [.finances, .merchandise, .contacts])
            }
            
            return accessibleModules
        }
        
        // Для других ролей, фильтруем модули по разрешениям
        return permissions?.modules
            .filter { $0.hasAccess(role: role) }
            .map { $0.moduleId } ?? []
    }
    
    // Получение доступных модулей для текущего пользователя
    func getCurrentUserAccessibleModules() -> [ModuleType] {
        guard let userRole = AppState.shared.user?.role else {
            return []
        }
        
        return getAccessibleModules(for: userRole)
    }
    
    // Проверка, имеет ли пользователь разрешение на редактирование для модуля
    // Это более строгое требование, обычно для администраторов и менеджеров
    func hasEditPermission(for moduleId: ModuleType) -> Bool {
        guard let role = AppState.shared.user?.role else {
            return false
        }
        
        // Только администраторы и менеджеры могут редактировать
        return role == .admin || role == .manager
    }
    
    // Сброс разрешений к значениям по умолчанию
    func resetToDefaults() {
        guard let groupId = AppState.shared.user?.groupId,
              let permissionId = permissions?.id else {
            errorMessage = "Невозможно сбросить разрешения: отсутствует группа или ID разрешений"
            return
        }
        
        isLoading = true
        
        // Удаляем текущие разрешения и создаем новые
        db.collection("permissions").document(permissionId).delete { [weak self] error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Ошибка удаления разрешений: \(error.localizedDescription)"
                } else {
                    self.createDefaultPermissions(for: groupId)
                }
            }
        }
    }
    
    // Получение списка ролей, имеющих доступ к модулю
    func getRolesWithAccess(to moduleId: ModuleType) -> [UserModel.UserRole] {
        if let modulePermission = permissions?.modules.first(where: { $0.moduleId == moduleId }) {
            return modulePermission.roleAccess
        }
        
        // Если модуль не найден, возвращаем роли по умолчанию
        switch moduleId {
        case .admin:
            return [.admin]
        case .finances, .merchandise, .contacts:
            return [.admin, .manager]
        case .calendar, .setlists, .tasks, .chats:
            return [.admin, .manager, .musician, .member]
        }
    }
}
