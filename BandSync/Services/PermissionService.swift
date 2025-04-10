//
//  PermissionService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
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
        // Automatic permission check when user changes
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
        print("PermissionService: listener removed")
    }
    
    // Get permissions for group
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
                    print("PermissionService: error loading permissions: \(error.localizedDescription)")
                    self.errorMessage = "Error loading permissions: \(error.localizedDescription)"
                    return
                }
                
                if let document = snapshot?.documents.first {
                    do {
                        let permissionModel = try document.data(as: PermissionModel.self)
                        DispatchQueue.main.async {
                            self.permissions = permissionModel
                            // Отправляем уведомление об обновлении данных
                            self.objectWillChange.send()
                            print("PermissionService: permissions loaded successfully")
                        }
                    } catch {
                        print("PermissionService: error converting permission data: \(error.localizedDescription)")
                        self.errorMessage = "Error converting permission data: \(error.localizedDescription)"
                        // Попытка создать объект вручную
                        let data = document.data()
                        self.createPermissionsFromData(document.documentID, data: data, groupId: groupId)
                    }
                } else {
                    // If no permissions for group, create default ones
                    print("PermissionService: no permissions found, creating defaults")
                    self.createDefaultPermissions(for: groupId)
                }
            }
    }
    
    // Ручное создание разрешений из данных
    private func createPermissionsFromData(_ documentId: String, data: [String: Any], groupId: String) {
        print("PermissionService: manual permission creation")
        
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
                print("PermissionService: permissions manually created")
            }
        } else {
            print("PermissionService: no modules data found")
        }
    }
    
    // Create default permissions for new group
    func createDefaultPermissions(for groupId: String) {
        isLoading = true
        
        // Default permissions for all modules
        let defaultModules: [PermissionModel.ModulePermission] = ModuleType.allCases.map { moduleType in
            // By default, admins and managers have access to everything
            // Regular members - only to calendar, setlists, tasks, and chats
            let roles: [UserModel.UserRole]
            
            switch moduleType {
            case .admin:
                // Only admins can access admin panel
                roles = [.admin]
            case .finances, .merchandise, .contacts:
                // Finances, merch, and contacts require manager rights
                roles = [.admin, .manager]
            case .calendar, .setlists, .tasks, .chats:
                // Basic modules available to all
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
                    print("PermissionService: error creating permissions: \(error.localizedDescription)")
                    self.errorMessage = "Error creating permissions: \(error.localizedDescription)"
                } else {
                    print("PermissionService: default permissions created")
                    // Load created permissions
                    self.fetchPermissions(for: groupId)
                }
            }
        } catch {
            isLoading = false
            print("PermissionService: error serializing permission data: \(error.localizedDescription)")
            errorMessage = "Error serializing permission data: \(error.localizedDescription)"
        }
    }
    
    // Update module permissions
    func updateModulePermission(moduleId: ModuleType, roles: [UserModel.UserRole]) {
        guard let permissionId = permissions?.id else {
            print("PermissionService: cannot update permissions, ID is missing")
            errorMessage = "Cannot update permissions: missing ID"
            return
        }
        
        isLoading = true
        
        // Find existing module to update
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
                            print("PermissionService: error updating permissions: \(error.localizedDescription)")
                            self.errorMessage = "Error updating permissions: \(error.localizedDescription)"
                        } else {
                            // Update local data
                            print("PermissionService: permissions updated successfully")
                            self.permissions?.modules = modules
                            
                            // Принудительно обновляем UI
                            self.objectWillChange.send()
                        }
                    }
                }
            } else {
                // Module not found, add it
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
                            print("PermissionService: error adding new module: \(error.localizedDescription)")
                            self.errorMessage = "Error adding new module: \(error.localizedDescription)"
                        } else {
                            print("PermissionService: new module added successfully")
                            self.permissions?.modules = modules
                            
                            // Принудительно обновляем UI
                            self.objectWillChange.send()
                        }
                    }
                }
            }
        } else {
            print("PermissionService: no modules found in current permissions")
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "No modules found in current permissions"
            }
        }
    }
    
    // Improved check if user has access to a module with safe defaults
    func hasAccess(to moduleId: ModuleType, role: UserModel.UserRole) -> Bool {
        // Admins always have access to everything
        if role == .admin {
            return true
        }
        
        // If permissions not loaded yet, use default safe values
        if permissions == nil {
            switch moduleId {
            case .admin:
                return role == .admin
            case .finances, .merchandise, .contacts:
                return role == .admin || role == .manager
            case .calendar, .setlists, .tasks, .chats:
                return true // Basic modules available to all by default
            }
        }
        
        // Check permissions from database
        if let modulePermission = permissions?.modules.first(where: { $0.moduleId == moduleId }) {
            return modulePermission.hasAccess(role: role)
        }
        
        // If module not found in permissions, use default values
        switch moduleId {
        case .admin:
            return role == .admin
        case .finances, .merchandise, .contacts:
            return role == .admin || role == .manager
        case .calendar, .setlists, .tasks, .chats:
            return true // Basic modules available to all by default
        }
    }
    
    // Check access for current user
    func currentUserHasAccess(to moduleId: ModuleType) -> Bool {
        guard let userRole = AppState.shared.user?.role else {
            return false
        }
        
        return hasAccess(to: moduleId, role: userRole)
    }
    
    // Get all modules that the user has access to
    func getAccessibleModules(for role: UserModel.UserRole) -> [ModuleType] {
        // Admins have access to everything
        if role == .admin {
            return ModuleType.allCases
        }
        
        // If permissions not loaded yet, use default values
        if permissions == nil {
            var accessibleModules: [ModuleType] = []
            
            // Basic modules for all users
            accessibleModules.append(contentsOf: [.calendar, .setlists, .tasks, .chats])
            
            // Additional modules for managers
            if role == .manager {
                accessibleModules.append(contentsOf: [.finances, .merchandise, .contacts])
            }
            
            return accessibleModules
        }
        
        // For other roles, filter modules by permissions
        return permissions?.modules
            .filter { $0.hasAccess(role: role) }
            .map { $0.moduleId } ?? []
    }
    
    // Get accessible modules for current user
    func getCurrentUserAccessibleModules() -> [ModuleType] {
        guard let userRole = AppState.shared.user?.role else {
            return []
        }
        
        return getAccessibleModules(for: userRole)
    }
    
    // Check if user has edit permission for a module
    // This is a stricter requirement, usually for admins and managers
    func hasEditPermission(for moduleId: ModuleType) -> Bool {
        guard let role = AppState.shared.user?.role else {
            return false
        }
        
        // Only admins and managers can edit
        return role == .admin || role == .manager
    }
    
    // Reset permissions to default values
    func resetToDefaults() {
        guard let groupId = AppState.shared.user?.groupId,
              let permissionId = permissions?.id else {
            errorMessage = "Cannot reset permissions: missing group or permission ID"
            return
        }
        
        isLoading = true
        
        // Delete current permissions and create new ones
        db.collection("permissions").document(permissionId).delete { [weak self] error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("PermissionService: error deleting permissions: \(error.localizedDescription)")
                    self.errorMessage = "Error deleting permissions: \(error.localizedDescription)"
                } else {
                    print("PermissionService: creating new default permissions")
                    self.createDefaultPermissions(for: groupId)
                }
            }
        }
    }
    
    // Get list of roles that have access to a module
    func getRolesWithAccess(to moduleId: ModuleType) -> [UserModel.UserRole] {
        if let modulePermission = permissions?.modules.first(where: { $0.moduleId == moduleId }) {
            return modulePermission.roleAccess
        }
        
        // If module not found, return default roles
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
