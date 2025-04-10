//
//  GroupDetailView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 04.04.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI
import FirebaseFirestore

struct GroupDetailView: View {
    @StateObject private var groupService = GroupService.shared
    @State private var showingInviteSheet = false
    @State private var showingCodeShare = false
    @State private var showingSettings = false
    @State private var groupName = ""
    @State private var isEditingName = false
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Хедер группы
                GroupHeaderView(
                    group: groupService.group,
                    isEditingName: $isEditingName,
                    groupName: $groupName,
                    onSave: saveGroupName
                )
                
                Divider()
                
                // Статистика группы
                GroupStatsView(
                    memberCount: groupService.groupMembers.count,
                    pendingCount: groupService.pendingMembers.count
                )
                
                Divider()
                
                // Код приглашения
                if let group = groupService.group {
                    InvitationCodeView(
                        code: group.code,
                        onShare: { showingCodeShare = true },
                        onRegenerate: showRegenerateAlert
                    )
                }
                
                Divider()
                
                // Действия
                ActionButtonsView(
                    onInvite: { showingInviteSheet = true },
                    onSettings: { showingSettings = true },
                    onMembers: { /* уже есть в навигации */ }
                )
                
                Spacer(minLength: 30)
                
                // Участники (предпросмотр)
                if !groupService.groupMembers.isEmpty {
                    MembersPreviewView(members: groupService.groupMembers)
                }
                
                // Ожидающие подтверждения
                if !groupService.pendingMembers.isEmpty {
                    PendingMembersView(
                        pendingMembers: groupService.pendingMembers,
                        onApprove: { userId in
                            groupService.approveUser(userId: userId)
                        },
                        onReject: { userId in
                            groupService.rejectUser(userId: userId)
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Информация о группе")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingInviteSheet = true }) {
                        Label("Пригласить участников", systemImage: "person.badge.plus")
                    }
                    
                    Button(action: { showingSettings = true }) {
                        Label("Настройки группы", systemImage: "gear")
                    }
                    
                    Button(action: showLeaveGroupAlert) {
                        Label("Покинуть группу", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if let groupId = AppState.shared.user?.groupId {
                groupService.fetchGroup(by: groupId)
                if let name = groupService.group?.name {
                    groupName = name
                }
            }
        }
        .onChange(of: groupService.group) { newGroup in
            if let name = newGroup?.name {
                groupName = name
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                primaryButton: .destructive(Text("Подтвердить")) {
                    if alertTitle == "Покинуть группу" {
                        leaveGroup()
                    } else if alertTitle == "Обновить код" {
                        groupService.regenerateCode()
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showingInviteSheet) {
            InviteUsersView()
        }
        .sheet(isPresented: $showingSettings) {
            if let groupId = AppState.shared.user?.groupId {
                GroupSettingsView()
            }
        }
        .sheet(isPresented: $showingCodeShare) {
            if let code = groupService.group?.code {
                ShareCodeView(code: code)
            }
        }
        .overlay(
            Group {
                if isLoading {
                    ProgressView()
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                }
            }
        )
    }
    
    // Улучшенное сохранение имени группы с лучшей обработкой ошибок
    private func saveGroupName() {
        guard !groupName.isEmpty else { return }
        
        isLoading = true
        
        // Сохраняем новое значение в локальную переменную
        let newGroupName = groupName
        
        groupService.updateGroupName(newGroupName) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                self.isEditingName = false
                
                if !success {
                    // Восстановить предыдущее имя в случае ошибки
                    if let originalName = self.groupService.group?.name {
                        self.groupName = originalName
                    }
                    
                    // Показать ошибку пользователю
                    self.alertTitle = "Ошибка"
                    self.alertMessage = "Не удалось обновить название группы. Пожалуйста, попробуйте еще раз."
                    self.showAlert = true
                }
            }
        }
    }
    
    private func showLeaveGroupAlert() {
        alertTitle = "Покинуть группу"
        alertMessage = "Вы уверены, что хотите покинуть группу? Если вы администратор, права должны быть переданы другому участнику заранее."
        showAlert = true
    }
    
    private func showRegenerateAlert() {
        alertTitle = "Обновить код"
        alertMessage = "Вы уверены, что хотите сгенерировать новый код приглашения? Старый код станет недействительным."
        showAlert = true
    }
    
    // Улучшенная функция выхода из группы с проверкой прав
    private func leaveGroup() {
        guard let userId = AppState.shared.user?.id,
              let groupId = AppState.shared.user?.groupId else { return }
        
        isLoading = true
        
        // Проверить, является ли пользователь администратором и есть ли другие администраторы
        let isAdmin = AppState.shared.user?.role == .admin
        let otherAdmins = groupService.groupMembers.filter { $0.role == .admin && $0.id != userId }
        
        if isAdmin && otherAdmins.isEmpty {
            // Если пользователь единственный администратор, показать предупреждение
            isLoading = false
            alertTitle = "Невозможно покинуть группу"
            alertMessage = "Вы единственный администратор группы. Пожалуйста, назначьте другого администратора перед выходом."
            showAlert = true
            return
        }
        
        // Удалить пользователя из группы
        groupService.removeUser(userId: userId) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    // Очистить groupId у пользователя
                    UserService.shared.clearUserGroup { _ in
                        // Обновить состояние приложения
                        AppState.shared.refreshAuthState()
                        dismiss()
                    }
                } else {
                    alertTitle = "Ошибка"
                    alertMessage = "Не удалось покинуть группу. Пожалуйста, попробуйте еще раз."
                    showAlert = true
                }
            }
        }
    }
}

// MARK: - Вспомогательные компоненты

struct GroupHeaderView: View {
    let group: GroupModel?
    @Binding var isEditingName: Bool
    @Binding var groupName: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if isEditingName {
                    TextField("Название группы", text: $groupName)
                        .font(.title2.bold())
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .submitLabel(.done)
                        .onSubmit {
                            onSave()
                        }
                    
                    Button(action: onSave) {
                        Text("Сохранить")
                            .foregroundColor(.blue)
                    }
                } else {
                    Text(group?.name ?? "Загрузка...")
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    Button(action: { isEditingName = true }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            if let createdDate = group?.createdAt {
                Text("Создана: \(formattedDate(createdDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct GroupStatsView: View {
    let memberCount: Int
    let pendingCount: Int
    
    var body: some View {
        HStack(spacing: 20) {
            StatItem(value: memberCount, label: "Участников", icon: "person.3")
            StatItem(value: pendingCount, label: "Ожидают", icon: "person.badge.clock")
        }
    }
}

struct StatItem: View {
    let value: Int
    let label: String
    let icon: String
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text("\(value)")
                    .font(.title3.bold())
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 100)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct InvitationCodeView: View {
    let code: String
    let onShare: () -> Void
    let onRegenerate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Код приглашения")
                .font(.headline)
            
            HStack {
                Text(code)
                    .font(.system(.title3, design: .monospaced))
                    .bold()
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                
                Spacer()
                
                Button(action: {
                    UIPasteboard.general.string = code
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.blue)
                }
                
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.blue)
                }
            }
            
            Button(action: onRegenerate) {
                Text("Сгенерировать новый код")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }
}

struct ActionButtonsView: View {
    let onInvite: () -> Void
    let onSettings: () -> Void
    let onMembers: () -> Void
    
    var body: some View {
        HStack(spacing: 15) {
            ActionButton(
                title: "Пригласить",
                icon: "person.badge.plus",
                action: onInvite
            )
            
            ActionButton(
                title: "Настройки",
                icon: "gear",
                action: onSettings
            )
            
            NavigationLink(destination: UsersListView()) {
                ActionButton(
                    title: "Участники",
                    icon: "person.3",
                    action: {}
                )
            }
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
    }
}

struct MembersPreviewView: View {
    let members: [UserModel]
    let maxDisplay = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Участники")
                .font(.headline)
            
            ForEach(members.prefix(maxDisplay)) { member in
                HStack {
                    Text(member.name)
                        .lineLimit(1)
                    Spacer()
                    Text(member.role.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 5)
            }
            
            if members.count > maxDisplay {
                NavigationLink(destination: UsersListView()) {
                    Text("Показать всех (\(members.count))")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct PendingMembersView: View {
    let pendingMembers: [UserModel]
    let onApprove: (String) -> Void
    let onReject: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ожидают подтверждения")
                .font(.headline)
            
            ForEach(pendingMembers) { member in
                HStack {
                    Text(member.name)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button(action: { onApprove(member.id) }) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                    }
                    
                    Button(action: { onReject(member.id) }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 5)
            }
        }
    }
}

struct InviteUsersView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var groupService = GroupService.shared
    @State private var inviteEmail = ""
    @State private var message = ""
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Пригласить по Email")) {
                    TextField("Email пользователя", text: $inviteEmail)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    Button("Отправить приглашение") {
                        sendInvite()
                    }
                    .disabled(inviteEmail.isEmpty || isLoading)
                }
                
                Section(header: Text("Код приглашения")) {
                    if let code = groupService.group?.code {
                        HStack {
                            Text(code)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                            
                            Spacer()
                            
                            Button(action: {
                                UIPasteboard.general.string = code
                                alertMessage = "Код скопирован в буфер обмена"
                                showAlert = true
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        
                        Text("Участники могут использовать этот код для присоединения к группе")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !message.isEmpty {
                    Section {
                        Text(message)
                            .foregroundColor(message.contains("Ошибка") ? .red : .green)
                    }
                }
            }
            .navigationTitle("Пригласить участников")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Информация"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .overlay(
                Group {
                    if isLoading {
                        ProgressView()
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(10)
                            .shadow(radius: 10)
                    }
                }
            )
            .onAppear {
                if let groupId = AppState.shared.user?.groupId {
                    groupService.fetchGroup(by: groupId)
                }
            }
        }
    }
    
    private func sendInvite() {
        guard let groupId = groupService.group?.id else {
            message = "Ошибка: не удалось загрузить информацию о группе"
            return
        }
        
        isLoading = true
        
        groupService.inviteUserByEmail(email: inviteEmail, to: groupId) { result in
            isLoading = false
            
            switch result {
            case .success:
                message = "Приглашение успешно отправлено!"
                inviteEmail = ""
            case .failure(let error):
                message = "Ошибка: \(error.localizedDescription)"
            }
        }
    }
}

struct ShareCodeView: View {
    let code: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Приглашение в группу BandSync")
                    .font(.title3)
                    .padding()
                
                Spacer()
                
                VStack(spacing: 15) {
                    Text("Используйте код")
                        .font(.headline)
                    
                    Text(code)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                    
                    Text("для присоединения к группе в приложении BandSync")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                Button(action: {
                    let text = "Привет! Присоединяйся к моей группе в BandSync. Используй код: \(code)"
                    UIPasteboard.general.string = text
                    
                    let activityVC = UIActivityViewController(
                        activityItems: [text],
                        applicationActivities: nil
                    )
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        rootViewController.present(activityVC, animated: true)
                    }
                }) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
            .padding()
            .navigationTitle("Поделиться кодом")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
            }
        }
    }
}
