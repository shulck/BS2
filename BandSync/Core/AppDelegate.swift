//
//  AppDelegate.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//

import UIKit
import Firebase
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Инициализация Firebase
        FirebaseApp.configure()
        
        // Настройка делегата уведомлений
        UNUserNotificationCenter.current().delegate = self
        
        // Настройка Firebase Messaging
        Messaging.messaging().delegate = self
        
        // Запрос разрешения на уведомления
        requestNotificationAuthorization()
        
        // Регистрация для удалённых уведомлений
        application.registerForRemoteNotifications()
        
        return true
    }
    
    // Запрос разрешения на уведомления
    private func requestNotificationAuthorization() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                if let error = error {
                    print("AppDelegate: ошибка запроса разрешения уведомлений: \(error)")
                } else {
                    print("AppDelegate: разрешение на уведомления \(granted ? "получено" : "отклонено")")
                }
            }
        )
    }
    
    // Получение FCM токена устройства
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            print("AppDelegate: FCM токен получен: \(token)")
            // Здесь можно сохранить токен на сервере или в пользовательском профиле
        }
    }
    
    // Прием удаленных уведомлений, когда приложение открыто
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Показать уведомление, даже если приложение открыто
        completionHandler([.banner, .sound, .badge])
    }
    
    // Обработка нажатия на уведомление
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        // Обработка данных уведомления
        if let type = userInfo["type"] as? String {
            switch type {
            case "event":
                // Навигация к событию
                if let eventId = userInfo["eventId"] as? String {
                    print("AppDelegate: нажатие на уведомление о событии: \(eventId)")
                    // Здесь код для навигации к событию
                }
            case "task":
                // Навигация к задаче
                if let taskId = userInfo["taskId"] as? String {
                    print("AppDelegate: нажатие на уведомление о задаче: \(taskId)")
                    // Здесь код для навигации к задаче
                }
            case "message":
                // Навигация к сообщению
                if let chatId = userInfo["chatId"] as? String {
                    print("AppDelegate: нажатие на уведомление о сообщении: \(chatId)")
                    // Здесь код для навигации к чату
                }
            default:
                break
            }
        }
        
        completionHandler()
    }
    
    // Получение токена устройства для удаленных уведомлений
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("AppDelegate: токен устройства для удаленных уведомлений: \(token)")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Обработка ошибки регистрации удаленных уведомлений
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("AppDelegate: ошибка регистрации удаленных уведомлений: \(error.localizedDescription)")
    }
    
    // Обработка URL открытия
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        print("AppDelegate: приложение открыто по URL: \(url)")
        return true
    }
    
    // Обработка входа приложения в фоновый режим
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("AppDelegate: приложение перешло в фоновый режим")
    }
    
    // Обработка возвращения приложения в активное состояние
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("AppDelegate: приложение возвращается в активное состояние")
        // Обновить состояние авторизации при возвращении из фонового режима
        AppState.shared.refreshAuthState()
    }
}
