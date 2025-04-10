//
//  AdminPanelView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 10.04.2025.
//

import SwiftUI
import FirebaseFirestore

struct AdminPanelView: View {
    @StateObject private var groupService = GroupService.shared
    @StateObject private var userService = UserService.shared
    @StateObject private var permissionService = PermissionService.shared
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var debugInfo: [String: Any] = [:]
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            List {
                // Отладочная секция
                if AppState.shared.user?.role == .admin {
                    Section(header: Text("Диагностика")) {
                        ForEach(debugInfo.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.caption)
                                Spacer()
                                Text("\(String(describing: value))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // Статистика группы
                Section(header: Text("Статистика группы")) {
                    StatisticRow(
                        title: "Администратор",
                        value: AppState.shared.user?.role.rawValue ?? "Не определена"
                    )
                    
                    StatisticRow(
                        title: "ID группы",
                        value: AppState.shared.user?.groupId ?? "Не указан"
                    )
                    
                    StatisticRow(
                        title: "Всего участников",
                        value: "\(groupService.groupMembers.count)"
                    )
                    
                    StatisticRow(
                        title: "Участники в ожидании",
                        value: "\(groupService.pendingMembers.count)"
                    )
                    
                    StatisticRow(
                        title: "Доступные модули",
                        value: "\(permissionService.getCurrentUserAccessibleModules().count) из \(ModuleType.allCases.count)"
                    )
                }
                
                // Управление группой
                Section(header: Text("Управление группой")) {
                    NavigationLink(destination: UsersListView()) {
                        Label("Список участников", systemImage: "person.3")
                    }
                    
                    NavigationLink(destination: GroupDetailView()) {
                        Label("Детали группы", systemImage: "info.circle")
                    }
                    
                    NavigationLink(destination: PermissionsView()) {
                        Label("Права доступа", systemImage: "lock.shield")
                    }
                    
                    NavigationLink(destination: GroupSettingsView()) {
                        Label("Настройки группы", systemImage: "gear")
                    }
                }
                
                // Действия
                Section(header: Text("Дополнительно")) {
                    Button(action: fetchCompleteGroupInfo) {
                        Label("Обновить информацию о группе", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                    
                    Button(action: regenerateGroupCode) {
                        Label("Сгенерировать новый код приглашения", systemImage: "arrow.2.squarepath")
                    }
                    .disabled(isRefreshing)
                }
                
                Spacer(minLength: 30)
                
                // Дополнительная секция для информации о правах
                if AppState.shared.user?.role == .admin {
                    Section(header: Text("Разрешения")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Текущие права доступа:")
                                .font(.subheadline)
                            
                            ForEach(permissionService.getCurrentUserAccessibleModules(), id: \.self) { module in
                                HStack {
                                    Image(systemName: module.icon)
                                        .foregroundColor(.blue)
                                    
                                    Text(module.displayName)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    // Показываем, какие роли имеют доступ
                                    let roles = permissionService.getRolesWithAccess(to: module)
                                    Text(roles.map { $0.rawValue.prefix(1) }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Панель администратора")
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadAdminPanelData()
            }
            .refreshable {
                await refreshData()
            }
            .overlay(
                Group {
                    if isRefreshing {
                        ProgressView()
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
            )
        }
    }
    
    private func loadAdminPanelData() {
        // Сбор диагностической информации
        debugInfo.removeAll()
        
        // Проверка текущего пользователя
        if let user = AppState.shared.user {
            debugInfo["Роль пользователя"] = user.role.rawValue
            debugInfo["Email пользователя"] = user.email
            debugInfo["ID пользователя"] = user.id ?? "Не определен"
            debugInfo["ID группы"] = user.groupId ?? "Не указан"
        }
        
        // Загрузка информации о группе
        guard let groupId = AppState.shared.user?.groupId else {
            alertTitle = "Ошибка"
            alertMessage = "Не удалось определить группу"
            showAlert = true
            return
        }
        
        // Расширенная загрузка группы
        groupService.fetchGroup(by: groupId)
        
        // Загрузка прав доступа
        permissionService.fetchPermissions(for: groupId)
        
        // Дополнительная диагностика
        Task {
            await fetchDetailedGroupInfo(groupId: groupId)
        }
    }
    
    private func fetchDetailedGroupInfo(groupId: String) async {
        do {
            let groupDoc = try await Firestore.firestore().collection("groups").document(groupId).getDocument()
            
            if let data = groupDoc.data() {
                // Отладочная информация о группе
                debugInfo["Название группы"] = data["name"] as? String ?? "Не указано"
                debugInfo["Код группы"] = data["code"] as? String ?? "Не указан"
                
                // Информация о членах группы
                let members = data["members"] as? [String] ?? []
                let pendingMembers = data["pendingMembers"] as? [String] ?? []
                
                debugInfo["Количество участников"] = members.count
                debugInfo["Количество ожидающих"] = pendingMembers.count
                
                // Список ID участников для отладки
                debugInfo["ID участников"] = members.prefix(3).joined(separator: ", ") + (members.count > 3 ? "..." : "")
            }
        } catch {
            debugInfo["Ошибка загрузки"] = error.localizedDescription
        }
    }
    
    // Асинхронная функция для обновления данных при pull-to-refresh
    private func refreshData() async {
        isRefreshing = true
        
        guard let groupId = AppState.shared.user?.groupId else {
            isRefreshing = false
            return
        }
        
        // Ожидаем выполнения всех операций параллельно
        await withTaskGroup(of: Void.self) { group in
            // Обновляем информацию о группе
            group.addTask {
                await withCheckedContinuation { continuation in
                    groupService.fetchGroup(by: groupId) { _ in
                        continuation.resume()
                    }
                }
            }
            
            // Обновляем разрешения
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async {
                        permissionService.fetchPermissions(for: groupId)
                        continuation.resume()
                    }
                }
            }
            
            // Обновляем дополнительную информацию
            group.addTask {
                await fetchDetailedGroupInfo(groupId: groupId)
            }
        }
        
        // Обновляем UI
        DispatchQueue.main.async {
            self.isRefreshing = false
            
            self.alertTitle = "Успех"
            self.alertMessage = "Информация обновлена"
            self.showAlert = true
        }
    }
    
    private func fetchCompleteGroupInfo() {
        guard let groupId = AppState.shared.user?.groupId else {
            alertTitle = "Ошибка"
            alertMessage = "Не удалось определить группу"
            showAlert = true
            return
        }
        
        isRefreshing = true
        
        // Принудительное обновление всех данных
        groupService.fetchGroup(by: groupId) { _ in
            // Обновляем разрешения
            DispatchQueue.main.async {
                permissionService.fetchPermissions(for: groupId)
                
                // Дополнительная диагностика
                Task {
                    await self.fetchDetailedGroupInfo(groupId: groupId)
                    
                    DispatchQueue.main.async {
                        self.isRefreshing = false
                        self.alertTitle = "Успех"
                        self.alertMessage = "Информация обновлена"
                        self.showAlert = true
                    }
                }
            }
        }
    }
    
    private func regenerateGroupCode() {
        isRefreshing = true
        
        groupService.regenerateCode()
        
        // Задержка для обновления UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isRefreshing = false
            self.alertTitle = "Успех"
            self.alertMessage = "Создан новый код приглашения"
            self.showAlert = true
        }
    }
}

// Вспомогательная структура для отображения статистики
struct StatisticRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
