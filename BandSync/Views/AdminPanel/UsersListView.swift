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
                // Секция с активными участниками
                if !groupService.groupMembers.isEmpty {
                    Section(header: Text("Участники")) {
                        ForEach(groupService.groupMembers) { user in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("Роль: \(user.role.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Кнопки действий
                                if user.id != AppState.shared.user?.id {
                                    Menu {
                                        Button("Изменить роль") {
                                            selectedUserId = user.id
                                            showingRoleView = true
                                        }
                                        
                                        Button("Удалить из группы", role: .destructive) {
                                            alertTitle = "Удалить пользователя"
                                            alertMessage = "Вы уверены, что хотите удалить \(user.name) из группы?"
                                            selectedUserId = user.id
                                            showAlert = true
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                } else {
                                    // Метка для текущего пользователя
                                    Text("Вы")
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                // Секция с ожидающими подтверждения
                if !groupService.pendingMembers.isEmpty {
                    Section(header: Text("Ожидают подтверждения")) {
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
                                
                                // Кнопки принять/отклонить
                                Button {
                                    groupService.approveUser(userId: user.id)
                                } label: {
                                    Text("Принять")
                                        .foregroundColor(.green)
                                }
                                
                                Button {
                                    groupService.rejectUser(userId: user.id)
                                } label: {
                                    Text("Отклонить")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                
                // Код приглашения
                if let group = groupService.group {
                    Section(header: Text("Код приглашения")) {
                        HStack {
                            Text(group.code)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                            
                            Spacer()
                            
                            Button {
                                UIPasteboard.general.string = group.code
                                alertTitle = "Успех"
                                alertMessage = "Код скопирован в буфер обмена"
                                showAlert = true
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        
                        Button("Создать новый код") {
                            alertTitle = "Обновить код"
                            alertMessage = "Создание нового кода сделает текущий недействительным. Вы уверены?"
                            showAlert = true
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
        .navigationTitle("Участники группы")
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
            if alertTitle == "Удалить пользователя" {
                return Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    primaryButton: .destructive(Text("Удалить")) {
                        groupService.removeUser(userId: selectedUserId)
                    },
                    secondaryButton: .cancel()
                )
            } else if alertTitle == "Обновить код" {
                return Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    primaryButton: .destructive(Text("Обновить")) {
                        groupService.regenerateCode()
                    },
                    secondaryButton: .cancel()
                )
            } else {
                return Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// Представление для выбора роли
struct RoleSelectionView: View {
    let userId: String
    @StateObject private var groupService = GroupService.shared
    @State private var selectedRole: UserModel.UserRole = .member
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Выберите роль")) {
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
            }
            .navigationTitle("Изменить роль")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Находим текущую роль пользователя
                if let user = groupService.groupMembers.first(where: { $0.id == userId }) {
                    selectedRole = user.role
                }
            }
        }
    }
}
