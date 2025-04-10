//
//  ContentView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 31.03.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @State private var isRefreshing = false

    var body: some View {
        VStack {
            if isRefreshing {
                // Показать экран загрузки
                ProgressView("Загрузка...")
            } else if !appState.isLoggedIn {
                // Не вошел в систему
                LoginView()
            } else if appState.user?.groupId == nil {
                // Нет группы
                GroupSelectionView()
            } else {
                // Пользователь имеет группу (как активный член или ожидает подтверждения)
                // Временно разрешаем доступ всем для отладки
                MainTabView()
                    .overlay(
                        // Если ожидает подтверждения, показываем уведомление
                        Group {
                            if appState.isPendingApproval {
                                VStack {
                                    Text("Статус: ожидание подтверждения")
                                        .padding()
                                        .background(Color.yellow.opacity(0.8))
                                        .cornerRadius(8)
                                    
                                    // Вывод отладочной информации
                                    Text("GroupID: \(appState.user?.groupId ?? "нет")")
                                    Text("UserID: \(appState.user?.id ?? "нет")")
                                    Text("Роль: \(appState.user?.role.rawValue ?? "нет")")
                                    
                                    if let group = GroupService.shared.group {
                                        Text("В pendingMembers: \(group.pendingMembers.contains(appState.user?.id ?? "") ? "да" : "нет")")
                                    } else {
                                        Text("Группа не загружена")
                                    }
                                }
                                .padding()
                            }
                        }
                    )
            }
        }
        .onAppear {
            refreshState()
        }
    }
    
    private func refreshState() {
        isRefreshing = true
        appState.refreshAuthState {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isRefreshing = false
            }
        }
    }
}
