//
//  GroupSettingsView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI
import FirebaseFirestore

struct GroupSettingsView: View {
    @StateObject private var groupService = GroupService.shared
    @State private var settings: GroupModel.GroupSettings?
    @State private var newName = ""
    @State private var showNameChangeAlert = false
    @State private var showCodeChangeAlert = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var showDeleteAlert = false
    @State private var alertMessage = ""
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        let hasEditRights = AppState.shared.user?.role == .admin || AppState.shared.user?.role == .manager
        
        Form {
            // Основная информация
            Section(header: Text("Основная информация")) {
                HStack {
                    Text("Название группы")
                    Spacer()
                    Text(groupService.group?.name ?? "")
                        .foregroundColor(.secondary)
                }
                
                if hasEditRights {
                    Button("Изменить название") {
                        newName = groupService.group?.name ?? ""
                        showNameChangeAlert = true
                    }
                }
                
                // Приглашения и доступ
                HStack {
                    Text("Код приглашения")
                    Spacer()
                    Text(groupService.group?.code ?? "")
                        .foregroundColor(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
                
                if hasEditRights {
                    Button("Обновить код") {
                        showCodeChangeAlert = true
                    }
                }
            }
            
            // Настройки доступа участников
            if let settings = settings, hasEditRights {
                Section(header: Text("Настройки доступа")) {
                    Toggle("Участники могут приглашать людей", isOn: Binding(
                        get: { settings.allowMembersToInvite },
                        set: { newValue in
                            var updatedSettings = settings
                            updatedSettings.allowMembersToInvite = newValue
                            updateSettings(updatedSettings)
                        }
                    ))
                    
                    Toggle("Участники могут создавать события", isOn: Binding(
                        get: { settings.allowMembersToCreateEvents },
                        set: { newValue in
                            var updatedSettings = settings
                            updatedSettings.allowMembersToCreateEvents = newValue
                            updateSettings(updatedSettings)
                        }
                    ))
                    
                    Toggle("Участники могут создавать сетлисты", isOn: Binding(
                        get: { settings.allowMembersToCreateSetlists },
                        set: { newValue in
                            var updatedSettings = settings
                            updatedSettings.allowMembersToCreateSetlists = newValue
                            updateSettings(updatedSettings)
                        }
                    ))
                    
                    Toggle("Разрешить гостевой доступ", isOn: Binding(
                        get: { settings.allowGuestAccess },
                        set: { newValue in
                            var updatedSettings = settings
                            updatedSettings.allowGuestAccess = newValue
                            updateSettings(updatedSettings)
                        }
                    ))
                }
            }
            
            // Настройки модулей
            if hasEditRights {
                Section(header: Text("Модули приложения")) {
                    NavigationLink(destination: ModuleManagementView()) {
                        Text("Управление модулями")
                    }
                }
            }
            
            // Участники группы
            Section(header: Text("Участники")) {
                NavigationLink(destination: UsersListView()) {
                    HStack {
                        Text("Управление участниками")
                        Spacer()
                        Text("\(groupService.groupMembers.count)")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Проверка на единственного администратора
            if AppState.shared.user?.role == .admin {
                let adminCount = groupService.groupMembers.filter { $0.role == .admin }.count
                
                if adminCount <= 1 {
                    Section {
                        Text("Вы единственный администратор. Пожалуйста, назначьте другого администратора перед удалением группы или выходом из нее.")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
            }
            
            // Дополнительные действия
            if hasEditRights {
                Section {
                    Button("Сбросить настройки по умолчанию") {
                        resetSettings()
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // Только для администраторов
            if AppState.shared.user?.role == .admin {
                Section {
                    Button("Удалить группу") {
                        showDeleteGroupAlert()
                    }
                    .foregroundColor(.red)
                }
            }
            
            // Отображение ошибок
            if let error = groupService.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            
            // Индикатор загрузки
            if isLoading || groupService.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Настройки группы")
        .onAppear {
            loadGroup()
        }
        .alert("Изменить название", isPresented: $showNameChangeAlert) {
            TextField("Название группы", text: $newName)
            Button("Отмена", role: .cancel) {}
            Button("Сохранить") {
                updateGroupName(newName)
            }
        } message: {
            Text("Введите новое название группы")
        }
        .alert("Обновить код", isPresented: $showCodeChangeAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Обновить") {
                groupService.regenerateCode()
            }
        } message: {
            Text("Старый код станет недействительным. Все участники, которые еще не присоединились, должны будут использовать новый код.")
        }
        .alert("Успех", isPresented: $showSuccessAlert) {
            Button("ОК") {}
        } message: {
            Text(alertMessage)
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("ОК") {}
        } message: {
            Text(alertMessage)
        }
        .alert("Удалить группу?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                deleteGroup()
            }
        } message: {
            Text("Вы уверены, что хотите полностью удалить группу? Это действие необратимо и приведет к потере всех данных группы.")
        }
    }
    
    // Загрузить информацию о группе
    private func loadGroup() {
        isLoading = true
        
        if let groupId = AppState.shared.user?.groupId {
            groupService.fetchGroup(by: groupId)
            
            // Дожидаемся загрузки данных
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let groupSettings = groupService.group?.settings {
                    self.settings = groupSettings
                } else {
                    // Создаем настройки по умолчанию, если их нет
                    self.settings = GroupModel.GroupSettings()
                }
                self.isLoading = false
            }
        } else {
            isLoading = false
        }
    }
    
    // Обновить название группы
    private func updateGroupName(_ name: String) {
        guard !name.isEmpty, name != groupService.group?.name else { return }
        
        isLoading = true
        groupService.updateGroupName(name) { success in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if success {
                    self.alertMessage = "Название группы обновлено"
                    self.showSuccessAlert = true
                } else {
                    self.alertMessage = "Не удалось обновить название группы"
                    self.showErrorAlert = true
                }
            }
        }
    }
    
    // Обновить настройки группы
    private func updateSettings(_ newSettings: GroupModel.GroupSettings) {
        guard let groupId = groupService.group?.id else { return }
        
        isLoading = true
        
        do {
            let data = try Firestore.Encoder().encode(newSettings)
            
            Firestore.firestore().collection("groups").document(groupId).updateData([
                "settings": data
            ]) { error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.alertMessage = "Ошибка обновления настроек: \(error.localizedDescription)"
                        self.showErrorAlert = true
                    } else {
                        self.settings = newSettings
                        
                        // Также обновляем локально хранимую группу
                        if var updatedGroup = self.groupService.group {
                            updatedGroup.settings = newSettings
                            self.groupService.group = updatedGroup
                            
                            // Явно отправляем сигнал обновления
                            self.groupService.objectWillChange.send()
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.alertMessage = "Ошибка кодирования настроек: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
        }
    }
    
    // Сбросить настройки к значениям по умолчанию
    private func resetSettings() {
        let defaultSettings = GroupModel.GroupSettings()
        updateSettings(defaultSettings)
    }
    
    // Показать предупреждение об удалении группы
    private func showDeleteGroupAlert() {
        // Проверка, является ли пользователь единственным администратором
        let adminCount = groupService.groupMembers.filter { $0.role == .admin }.count
        
        if adminCount <= 1 {
            // Проверяем, есть ли другие участники
            let memberCount = groupService.groupMembers.count
            
            if memberCount > 1 {
                // Если есть другие участники, предупреждаем о необходимости назначить другого администратора
                self.alertMessage = "Вы единственный администратор группы. Пожалуйста, назначьте другого администратора перед удалением группы."
                self.showErrorAlert = true
                return
            }
        }
        
        // Если проверки пройдены, показываем диалог подтверждения
        showDeleteAlert = true
    }
    
    // Удалить группу
    private func deleteGroup() {
        guard let groupId = groupService.group?.id,
              AppState.shared.user?.role == .admin else { return }
        
        isLoading = true
        
        // Функция для очистки groupId у всех пользователей группы
        func clearUserGroupIds(members: [String], completion: @escaping () -> Void) {
            let group = DispatchGroup()
            
            for userId in members {
                group.enter()
                Firestore.firestore().collection("users").document(userId).updateData([
                    "groupId": NSNull()
                ]) { _ in
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion()
            }
        }
        
        // Получить полную модель группы, чтобы иметь доступ ко всем участникам
        Firestore.firestore().collection("groups").document(groupId).getDocument { snapshot, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.alertMessage = "Ошибка получения данных группы: \(error.localizedDescription)"
                    self.showErrorAlert = true
                }
                return
            }
            
            if let group = try? snapshot?.data(as: GroupModel.self) {
                // Объединить всех участников и ожидающих в один список
                let allMembers = Array(Set(group.members + group.pendingMembers))
                
                // Очистить groupId у всех пользователей
                clearUserGroupIds(members: allMembers) {
                    // Удалить группу
                    Firestore.firestore().collection("groups").document(groupId).delete { error in
                        DispatchQueue.main.async {
                            self.isLoading = false
                            
                            if let error = error {
                                self.alertMessage = "Ошибка удаления группы: \(error.localizedDescription)"
                                self.showErrorAlert = true
                            } else {
                                // Обновить состояние приложения
                                AppState.shared.refreshAuthState()
                                self.dismiss()
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.alertMessage = "Ошибка получения данных группы"
                    self.showErrorAlert = true
                }
            }
        }
    }
}
