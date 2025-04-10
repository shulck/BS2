//
//  SettingsView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 09.04.2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var localizationManager = LocalizationManager.shared
    @State private var showingLanguagePicker = false
    @State private var showingThemePicker = false
    @State private var showingNotificationSettings = false
    @State private var showingCacheSettings = false
    @State private var showingAbout = false
    @State private var showLogoutConfirmation = false
    
    // Доступные темы для приложения
    enum AppTheme: String, CaseIterable, Identifiable {
        case light = "Light"
        case dark = "Dark"
        case system = "System"
        
        var id: String { rawValue }
    }
    
    // Системная тема по умолчанию
    @State private var selectedTheme: AppTheme = .system
    
    // Строки для локализации
    private var interfaceLanguageText: String { "Interface Language".localized }
    private var themeText: String { "Theme".localized }
    private var notificationsText: String { "Notifications".localized }
    private var cacheAndStorageText: String { "Cache & Storage".localized }
    private var aboutText: String { "About".localized }
    private var versionText: String { "Version".localized }
    private var signOutText: String { "Sign Out".localized }
    private var cancelText: String { "Cancel".localized }
    private var confirmText: String { "Confirm".localized }
    private var logoutConfirmationText: String { "Are you sure you want to sign out?".localized }
    
    var body: some View {
        NavigationView {
            List {
                // Секция пользователя
                if let user = appState.user {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name)
                                .font(.headline)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Role: \(user.role.rawValue)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Языковые настройки
                Section(header: Text(interfaceLanguageText)) {
                    Button(action: {
                        showingLanguagePicker = true
                    }) {
                        HStack {
                            Text(localizationManager.currentLanguage.name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Настройки темы
                Section(header: Text(themeText)) {
                    Button(action: {
                        showingThemePicker = true
                    }) {
                        HStack {
                            Text(selectedTheme.rawValue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Настройки уведомлений
                Section(header: Text(notificationsText)) {
                    Button(action: {
                        showingNotificationSettings = true
                    }) {
                        HStack {
                            Text(notificationsText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Кеш и хранилище
                Section(header: Text(cacheAndStorageText)) {
                    Button(action: {
                        showingCacheSettings = true
                    }) {
                        HStack {
                            Text(cacheAndStorageText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // О приложении
                Section(header: Text(aboutText)) {
                    Button(action: {
                        showingAbout = true
                    }) {
                        HStack {
                            Text(aboutText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    HStack {
                        Text(versionText)
                        Spacer()
                        Text("1.0.0 (1)")
                            .foregroundColor(.gray)
                    }
                }
                
                // Кнопка выхода из аккаунта
                Section {
                    Button(action: {
                        showLogoutConfirmation = true
                    }) {
                        HStack {
                            Spacer()
                            Text(signOutText)
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingLanguagePicker) {
                LanguageSelectionView()
            }
            .sheet(isPresented: $showingThemePicker) {
                ThemeSelectionView(selectedTheme: $selectedTheme)
            }
            .sheet(isPresented: $showingNotificationSettings) {
                NotificationSettingsView()
            }
            .sheet(isPresented: $showingCacheSettings) {
                CacheSettingsView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .alert(isPresented: $showLogoutConfirmation) {
                Alert(
                    title: Text(signOutText),
                    message: Text(logoutConfirmationText),
                    primaryButton: .destructive(Text(confirmText)) {
                        appState.logout()
                    },
                    secondaryButton: .cancel(Text(cancelText))
                )
            }
        }
    }
}

// Представление для выбора языка
struct LanguageSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var localizationManager = LocalizationManager.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(LocalizationManager.Language.allCases) { language in
                    Button(action: {
                        localizationManager.currentLanguage = language
                        dismiss()
                    }) {
                        HStack {
                            Text(language.name)
                            Spacer()
                            if localizationManager.currentLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Language")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Представление для выбора темы
struct ThemeSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedTheme: SettingsView.AppTheme
    
    var body: some View {
        NavigationView {
            List {
                ForEach(SettingsView.AppTheme.allCases) { theme in
                    Button(action: {
                        selectedTheme = theme
                        applyTheme(theme)
                        dismiss()
                    }) {
                        HStack {
                            Text(theme.rawValue)
                            Spacer()
                            if selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Select Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // Применение темы (будет реализовано позже)
    private func applyTheme(_ theme: SettingsView.AppTheme) {
        // В iOS 13+ можно использовать UIApplication.shared.windows для установки темы,
        // а в iOS 15+ предпочтительнее использовать UIApplication.shared.connectedScenes
        
        // Пример кода для установки темы:
        // if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        //    let window = windowScene.windows.first {
        //     window.overrideUserInterfaceStyle = theme == .dark ? .dark : theme == .light ? .light : .unspecified
        // }
        
        // Сохранение в UserDefaults
        UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
    }
}

// Представление с информацией о приложении
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "music.mic")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.blue)
                        .padding()
                    
                    Text("BandSync")
                        .font(.largeTitle.bold())
                    
                    Text("Version 1.0.0 (1)")
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.vertical)
                    
                    Text("BandSync is the perfect tool for musicians and bands to organize their performances, manage setlists, track finances, and collaborate with team members.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Divider()
                        .padding(.vertical)
                    
                    Text("© 2025 BandSync Team")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("All rights reserved")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
