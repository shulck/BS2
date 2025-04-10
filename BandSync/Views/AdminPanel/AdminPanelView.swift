//
//  AdminPanelView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 04.04.2025.
//

import SwiftUI
import FirebaseFirestore

struct AdminPanelView: View {
    @StateObject private var groupService = GroupService.shared
    @StateObject private var userService = UserService.shared
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var debugInfo: [String: Any] = [:]
    
    var body: some View {
        NavigationView {
            List {
                // Отладочная секция
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
                }
                
                // Действия
                Section(header: Text("Дополнительно")) {
                    Button(action: fetchCompleteGroupInfo) {
                        Label("Обновить информацию о группе", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: regenerateGroupCode) {
                        Label("Сгенерировать новый код приглашения", systemImage: "arrow.2.squarepath")
                    }
                }
            }
            .navigationTitle("Панель администратора")
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Информация"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                loadAdminPanelData()
            }
            .refreshable {
                loadAdminPanelData()
            }
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
            alertMessage = "Не удалось определить группу"
            showAlert = true
            return
        }
        
        // Расширенная загрузка группы
        groupService.fetchGroup(by: groupId)
        
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
                debugInfo["ID участников"] = members.joined(separator: ", ")
            }
        } catch {
            debugInfo["Ошибка загрузки"] = error.localizedDescription
        }
    }
    
    private func fetchCompleteGroupInfo() {
        guard let groupId = AppState.shared.user?.groupId else {
            alertMessage = "Не удалось определить группу"
            showAlert = true
            return
        }
        
        // Принудительное обновление всех данных
        groupService.fetchGroup(by: groupId)
        
        alertMessage = "Информация обновлена"
        showAlert = true
    }
    
    private func regenerateGroupCode() {
        groupService.regenerateCode()
        
        alertMessage = "Создан новый код приглашения"
        showAlert = true
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
