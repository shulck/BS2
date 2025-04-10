//
//  UsersListView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI

struct UsersListView: View {
    @StateObject private var groupService = GroupService.shared
    @State private var showingRoleView = false
    @State private var selectedUserId = ""
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            if groupService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                // Group members
                if !groupService.groupMembers.isEmpty {
                    Section(header: Text("Members")) {
                        ForEach(groupService.groupMembers) { user in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("Role: \(user.role.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Action buttons
                                if user.id != AppState.shared.user?.id {
                                    Menu {
                                        Button("Change role") {
                                            selectedUserId = user.id
                                            showingRoleView = true
                                        }
                                        
                                        Button("Remove from group", role: .destructive) {
                                            confirmRemoveUser(user)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                } else {
                                    // Метка для текущего пользователя
                                    Text("You")
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                // Отображение информации о последнем админе
                let adminCount = groupService.groupMembers.filter { $0.role == .admin }.count
                if adminCount <= 1 {
                    Section {
                        Text("Внимание: В группе должен быть хотя бы один администратор.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // Pending approvals
                if !groupService.pendingMembers.isEmpty {
                    Section(header: Text("Awaiting approval")) {
                        ForEach(groupService.pendingMembers) { user in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                // Accept/reject buttons
                                Button {
                                    groupService.approveUser(userId: user.id)
                                } label: {
                                    Text("Accept")
                                        .foregroundColor(.green)
                                }
                                
                                Button {
                                    groupService.rejectUser(userId: user.id)
                                } label: {
                                    Text("Decline")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                // Invitation code
                if let group = groupService.group {
                    Section(header: Text("Invitation code")) {
                        HStack {
                            Text(group.code)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = group.code
                                showCopiedAlert()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        
                        Button("Generate new code") {
                            confirmRegenerateCode()
                        }
                    }
                }
            }
            
            if let error = groupService.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Group members")
        .onAppear {
            if let gid = AppState.shared.user?.groupId {
                groupService.fetchGroup(by: gid)
            }
        }
        .sheet(isPresented: $showingRoleView) {
            RoleSelectionView(userId: selectedUserId)
        }
        .refreshable {
            if let gid = AppState.shared.user?.groupId {
                groupService.fetchGroup(by: gid)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Confirm")) {
                    if alertTitle == "Remove User" {
                        removeUser(selectedUserId)
                    } else if alertTitle == "Regenerate Code" {
                        groupService.regenerateCode()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // Подтверждение удаления пользователя
    private func confirmRemoveUser(_ user: UserModel) {
        selectedUserId = user.id
        alertTitle = "Remove User"
        alertMessage = "Are you sure you want to remove \(user.name) from the group?"
        showAlert = true
    }
    
    // Подтверждение смены кода
    private func confirmRegenerateCode() {
        alertTitle = "Regenerate Code"
        alertMessage = "Creating a new code will invalidate the current one. Are you sure?"
        showAlert = true
    }
    
    // Удаление пользователя с обработкой ошибок
    private func removeUser(_ userId: String) {
        groupService.removeUser(userId: userId) { success in
            if !success {
                // Показываем сообщение об ошибке
                alertTitle = "Error"
                alertMessage = "Failed to remove user. Please try again."
                showAlert = true
            }
        }
    }
    
    // Показать алерт о копировании кода
    private func showCopiedAlert() {
        alertTitle = "Success"
        alertMessage = "Invitation code copied to clipboard"
        showAlert = true
    }
}

// Role selection view
struct RoleSelectionView: View {
    let userId: String
    @StateObject private var groupService = GroupService.shared
    @State private var selectedRole: UserModel.UserRole = .member
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Select a role")) {
                    ForEach(UserModel.UserRole.allCases, id: \.self) { role in
                        Button {
                            selectedRole = role
                            groupService.changeUserRole(userId: userId, newRole: role)
                            dismiss()
                        } label: {
                            HStack {
                                Text(role.rawValue)
                                Spacer()
                                if selectedRole == role {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                
                // Выводим предупреждение, если пытаемся изменить роль последнего админа
                if isLastAdmin() && selectedRole != .admin {
                    Section {
                        Text("This is the last administrator. You must maintain at least one admin in the group.")
                            .foregroundColor(.red)
                    }
                }
                
                if groupService.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                
                if let error = groupService.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Change role")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Try to find the user's current role
            if let user = groupService.groupMembers.first(where: { $0.id == userId }) {
                selectedRole = user.role
            }
        }
        .onDisappear {
            // Обновляем группу при закрытии формы
            if let groupId = AppState.shared.user?.groupId {
                groupService.fetchGroup(by: groupId)
            }
        }
    }
    
    // Проверяем, является ли пользователь последним админом
    private func isLastAdmin() -> Bool {
        let user = groupService.groupMembers.first(where: { $0.id == userId })
        if user?.role == .admin {
            let adminCount = groupService.groupMembers.filter { $0.role == .admin }.count
            if adminCount <= 1 {
                return true
            }
        }
        return false
    }
}
