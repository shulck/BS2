//
//  ModuleManagementView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI

struct ModuleManagementView: View {
    @StateObject private var permissionService = PermissionService.shared
    @State private var modules = ModuleType.allCases
    @State private var enabledModules: Set<ModuleType> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showConfirmationAlert = false
    @State private var moduleToToggle: ModuleType?
    @State private var confirmationMessage = ""
    @State private var isEnabling = false
    
    var body: some View {
        List {
            Section(header: Text("Available modules")) {
                Text("Enable or disable modules that will be available to group members.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            
            ForEach(modules) { module in
                HStack {
                    Image(systemName: module.icon)
                        .foregroundColor(.blue)
                    
                    Text(module.displayName)
                    
                    Spacer()
                    
                    if module == .admin {
                        Text("Always enabled")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { enabledModules.contains(module) },
                            set: { newValue in
                                // Вместо прямого изменения, сначала показываем подтверждение
                                moduleToToggle = module
                                isEnabling = newValue
                                
                                if newValue {
                                    confirmationMessage = "Are you sure you want to enable the \(module.displayName) module?"
                                } else {
                                    confirmationMessage = "Are you sure you want to disable the \(module.displayName) module? Users will no longer have access to this functionality."
                                }
                                
                                showConfirmationAlert = true
                            }
                        ))
                    }
                }
            }
            
            Section {
                Button("Save changes") {
                    saveChanges()
                }
                .disabled(isLoading)
            }
            
            // Success or error messages
            if let success = successMessage {
                Section {
                    Text(success)
                        .foregroundColor(.green)
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            // Loading indicator
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Module management")
        .onAppear {
            loadModuleSettings()
        }
        .alert(isPresented: $showConfirmationAlert) {
            Alert(
                title: Text("Confirm Module Change"),
                message: Text(confirmationMessage),
                primaryButton: .default(Text("Continue")) {
                    if let module = moduleToToggle {
                        if isEnabling {
                            enabledModules.insert(module)
                        } else {
                            enabledModules.remove(module)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .refreshable {
            loadModuleSettings()
        }
    }
    
    // Load current module settings
    private func loadModuleSettings() {
        isLoading = true
        successMessage = nil
        errorMessage = nil
        
        if let groupId = AppState.shared.user?.groupId {
            permissionService.fetchPermissions(for: groupId)
            
            // Use delay to give time for permissions to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Initialize list of enabled modules
                enabledModules = Set(permissionService.permissions?.modules
                    .filter { !$0.roleAccess.isEmpty }
                    .map { $0.moduleId } ?? [])
                
                // Admin is always enabled
                enabledModules.insert(.admin)
                
                isLoading = false
            }
        } else {
            isLoading = false
            errorMessage = "Could not determine group"
        }
    }
    
    // Save changes
    private func saveChanges() {
        guard let permissionId = permissionService.permissions?.id else {
            errorMessage = "Could not find permission settings"
            return
        }
        
        isLoading = true
        successMessage = nil
        errorMessage = nil
        
        // Создаем словарь изменений для отслеживания и логирования
        var changes: [String: Bool] = [:]
        
        // For each module except Admin
        for module in modules where module != .admin {
            // Определяем, было ли изменение
            let wasEnabled = permissionService.getRolesWithAccess(to: module).isEmpty == false
            let isNowEnabled = enabledModules.contains(module)
            
            if wasEnabled != isNowEnabled {
                changes[module.displayName] = isNowEnabled
            }
            
            // Determine which roles should have access
            let roles: [UserModel.UserRole]
            
            if enabledModules.contains(module) {
                // If module is enabled, use current role settings or defaults
                roles = permissionService.getRolesWithAccess(to: module)
                
                // If no roles, set default access settings
                if roles.isEmpty {
                    switch module {
                    case .finances, .merchandise, .contacts:
                        // Finances, merch and contacts require management rights
                        permissionService.updateModulePermission(
                            moduleId: module,
                            roles: [.admin, .manager]
                        )
                    case .calendar, .setlists, .tasks, .chats:
                        // Basic modules available to all
                        permissionService.updateModulePermission(
                            moduleId: module,
                            roles: [.admin, .manager, .musician, .member]
                        )
                    default:
                        break
                    }
                }
            } else {
                // If module is disabled, set empty role list
                permissionService.updateModulePermission(
                    moduleId: module,
                    roles: []
                )
            }
        }
        
        // Delay to complete all update operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isLoading = false
            
            // Формируем информативное сообщение об успехе
            if changes.isEmpty {
                successMessage = "No changes were made"
            } else {
                let changeMessages = changes.map { "\($0.key): \($0.value ? "enabled" : "disabled")" }
                successMessage = "Module settings successfully updated.\nChanges: \(changeMessages.joined(separator: ", "))"
            }
            
            // Загружаем обновленные настройки
            self.loadModuleSettings()
        }
    }
}
