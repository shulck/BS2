//
//  PermissionsView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI

struct PermissionsView: View {
    @StateObject private var permissionService = PermissionService.shared
    @State private var selectedModule: ModuleType?
    @State private var showModuleEditor = false
    @State private var showResetConfirmation = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    
    var body: some View {
        List {
            // Information section
            Section(header: Text("Access management")) {
                Text("Here you can configure which roles have access to different application modules.")
                    .font(.footnote)
            }
            
            // Modules section
            Section(header: Text("Modules")) {
                ForEach(ModuleType.allCases) { module in
                    Button {
                        selectedModule = module
                        showModuleEditor = true
                    } label: {
                        HStack {
                            Image(systemName: module.icon)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text(module.displayName)
                                    .foregroundColor(.primary)
                                
                                // Display roles with access
                                Text(accessRolesText(for: module))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
            }
            
            // Reset settings
            Section {
                Button("Reset to default values") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
            }
            
            // Loading indicator
            if permissionService.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            
            // Error message
            if let error = permissionService.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Permissions")
        .sheet(isPresented: $showModuleEditor) {
            if let module = selectedModule {
                ModulePermissionEditorView(module: module)
            }
        }
        .alert("Reset permissions?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                permissionService.resetToDefaults()
                successMessage = "Permissions reset to default values"
                showSuccessAlert = true
            }
        } message: {
            Text("This action will reset all permission settings to default values. Are you sure?")
        }
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage)
        }
        .onAppear {
            if let groupId = AppState.shared.user?.groupId {
                permissionService.fetchPermissions(for: groupId)
            }
        }
        .refreshable {
            if let groupId = AppState.shared.user?.groupId {
                permissionService.fetchPermissions(for: groupId)
            }
        }
    }
    
    // Format text of roles with access
    private func accessRolesText(for module: ModuleType) -> String {
        let roles = permissionService.getRolesWithAccess(to: module)
        
        if roles.isEmpty {
            return "No access"
        }
        
        return roles.map { $0.rawValue }.joined(separator: ", ")
    }
}

// Module permission editor
struct ModulePermissionEditorView: View {
    let module: ModuleType
    @StateObject private var permissionService = PermissionService.shared
    @Environment(\.dismiss) var dismiss
    @State private var showSuccessAlert = false
    
    // Local state of selected roles
    @State private var selectedRoles: Set<UserModel.UserRole> = []
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Module access")) {
                    Text("Select roles that will have access to the '\(module.displayName)' module")
                        .font(.footnote)
                }
                
                Section(header: Text("Roles")) {
                    ForEach(UserModel.UserRole.allCases, id: \.self) { role in
                        Button {
                            toggleRole(role)
                        } label: {
                            HStack {
                                Text(role.rawValue)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if selectedRoles.contains(role) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                if permissionService.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(module.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePermissions()
                    }
                }
            }
            .onAppear {
                // Load current roles when appearing
                let currentRoles = permissionService.getRolesWithAccess(to: module)
                selectedRoles = Set(currentRoles)
            }
            .alert("Permissions Updated", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Access settings for \(module.displayName) have been updated.")
            }
        }
    }
    
    // Toggle role selection
    private func toggleRole(_ role: UserModel.UserRole) {
        if selectedRoles.contains(role) {
            selectedRoles.remove(role)
        } else {
            selectedRoles.insert(role)
        }
    }
    
    // Save settings
    private func savePermissions() {
        permissionService.updateModulePermission(
            moduleId: module,
            roles: Array(selectedRoles)
        )
        
        // Показываем сообщение об успехе
        showSuccessAlert = true
    }
}
