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
        print("AppDelegate: initialization started")
        
        // Single Firebase initialization - this is the only place to initialize Firebase
        FirebaseApp.configure()
        print("AppDelegate: Firebase initialized")
        
        // Notification setup
        UNUserNotificationCenter.current().delegate = self
        print("AppDelegate: notification delegate set")
        
        // Firebase Messaging setup
        Messaging.messaging().delegate = self
        print("AppDelegate: Messaging delegate set")
        
        // Request notification permission
        requestNotificationAuthorization()
        
        print("AppDelegate: initialization completed")
        return true
    }
    
    // Request notification permissions
    private func requestNotificationAuthorization() {
        print("AppDelegate: requesting notification permission")
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                print("AppDelegate: notification permission \(granted ? "granted" : "denied")")
                if let error = error {
                    print("AppDelegate: permission request error: \(error)")
                }
            }
        )
        
        UIApplication.shared.registerForRemoteNotifications()
        print("AppDelegate: registration for remote notifications requested")
    }
    
    // Get FCM device token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let token = fcmToken {
            print("AppDelegate: FCM token received: \(token)")
        } else {
            print("AppDelegate: failed to get FCM token")
        }
    }
    
    // Receive remote notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("AppDelegate: notification received in foreground")
        // Show notification even if app is open
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("AppDelegate: notification tap received: \(userInfo)")
        
        completionHandler()
    }
    
    // Get device token for remote notifications
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("AppDelegate: device token for remote notifications received: \(token)")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // Handle remote notification registration error
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("AppDelegate: failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // Handle URL opening
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        print("AppDelegate: app opened via URL: \(url)")
        return true
    }
    
    // Handle app entering background mode
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("AppDelegate: app entered background mode")
    }
    
    // Handle app returning to active state
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("AppDelegate: app returning to active state")
        // Update auth state when returning from background
        AppState.shared.refreshAuthState()
    }
}
