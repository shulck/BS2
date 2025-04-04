//
//  EventService.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//  Updated by Claude AI on 03.04.2025.
//

import Foundation
import FirebaseFirestore
import Network

final class EventService: ObservableObject {
    static let shared = EventService()

    @Published var events: [Event] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isOfflineMode: Bool = false
    
    private let db = Firestore.firestore()
    private var networkMonitor = NWPathMonitor()
    private var hasLoadedFromCache = false
    
    init() {
        // Initialize network monitoring
        setupNetworkMonitoring()
    }
    
    // Set up network monitoring
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let isConnected = path.status == .satisfied
                self?.isOfflineMode = !isConnected
                
                // When connection is restored, update data
                if isConnected && self?.hasLoadedFromCache == true {
                    if let groupId = AppState.shared.user?.groupId {
                        self?.fetchEvents(for: groupId)
                    }
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }

    func fetchEvents(for groupId: String) {
        isLoading = true
        errorMessage = nil
        
        // Check network connection
        if isOfflineMode {
            loadFromCache(groupId: groupId)
            return
        }
        
        db.collection("events")
            .whereField("groupId", isEqualTo: groupId)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error loading events: \(error.localizedDescription)"
                        self.loadFromCache(groupId: groupId)
                        return
                    }
                    
                    if let docs = snapshot?.documents {
                        let events = docs.compactMap { try? $0.data(as: Event.self) }
                        self.events = events
                        
                        // Save to cache
                        CacheService.shared.cacheEvents(events, forGroupId: groupId)
                    }
                }
            }
    }
    
    // Load from cache
    private func loadFromCache(groupId: String) {
        if let cachedEvents = CacheService.shared.getCachedEvents(forGroupId: groupId) {
            self.events = cachedEvents
            self.hasLoadedFromCache = true
            self.isLoading = false
            
            if isOfflineMode {
                self.errorMessage = "Loaded from cache (offline mode)"
            }
        } else {
            self.errorMessage = "No data available in offline mode"
            self.isLoading = false
        }
    }

    func addEvent(_ event: Event, completion: @escaping (Bool) -> Void) {
        isLoading = true
        errorMessage = nil
        
        // Check network connection
        if isOfflineMode {
            errorMessage = "Cannot add events in offline mode"
            isLoading = false
            completion(false)
            return
        }
        
        do {
            _ = try db.collection("events").addDocument(from: event) { [weak self] error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error adding event: \(error.localizedDescription)"
                        completion(false)
                    } else {
                        // Update local data
                        self.fetchEvents(for: event.groupId)
                        
                        // Schedule notifications
                        NotificationManager.shared.scheduleEventNotification(event: event)
                        
                        completion(true)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Event serialization error: \(error)"
                completion(false)
            }
        }
    }

    func updateEvent(_ event: Event, completion: @escaping (Bool) -> Void) {
        guard let id = event.id else {
            completion(false)
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Check network connection
        if isOfflineMode {
            errorMessage = "Cannot update events in offline mode"
            isLoading = false
            completion(false)
            return
        }
        
        do {
            try db.collection("events").document(id).setData(from: event) { [weak self] error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error updating event: \(error.localizedDescription)"
                        completion(false)
                    } else {
                        // Update local data
                        self.fetchEvents(for: event.groupId)
                        
                        // Update notifications
                        // First cancel old ones
                        NotificationManager.shared.cancelNotification(withIdentifier: "event_day_before_\(id)")
                        NotificationManager.shared.cancelNotification(withIdentifier: "event_hour_before_\(id)")
                        // Then schedule new ones
                        NotificationManager.shared.scheduleEventNotification(event: event)
                        
                        completion(true)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Event serialization error: \(error)"
                completion(false)
            }
        }
    }

    func deleteEvent(_ event: Event) {
            guard let id = event.id else { return }
            
            isLoading = true
            errorMessage = nil
            
            // Check network connection
            if isOfflineMode {
                errorMessage = "Cannot delete events in offline mode"
                isLoading = false
                return
            }
            
            db.collection("events").document(id).delete { [weak self] error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = "Error deleting: \(error.localizedDescription)"
                    } else if let groupId = AppState.shared.user?.groupId {
                        // Update local data
                        self.fetchEvents(for: groupId)
                        
                        // Cancel notifications
                        NotificationManager.shared.cancelNotification(withIdentifier: "event_day_before_\(id)")
                        NotificationManager.shared.cancelNotification(withIdentifier: "event_hour_before_\(id)")
                    }
                }
            }
        }
        
        // Get events filtered by date
        func eventsForDate(_ date: Date) -> [Event] {
            return events.filter {
                Calendar.current.isDate($0.date, inSameDayAs: date)
            }
        }
        
        // Get upcoming events
        func upcomingEvents(limit: Int = 5) -> [Event] {
            let now = Date()
            return events
                .filter { $0.date > now }
                .sorted { $0.date < $1.date }
                .prefix(limit)
                .map { $0 }
        }
        
        // Get events by type
        func eventsByType(_ type: EventType) -> [Event] {
            return events.filter { $0.type == type }
        }
        
        // Get events for a specific period
        func events(from startDate: Date, to endDate: Date) -> [Event] {
            return events.filter {
                $0.date >= startDate && $0.date <= endDate
            }
        }
        
        // Get events for a specific month and year
        func eventsForMonth(month: Int, year: Int) -> [Event] {
            let calendar = Calendar.current
            
            guard let startDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
                return []
            }
            
            return events(from: startDate, to: endDate)
        }
        
        // Clear all data
        func clearAllData() {
            events = []
            errorMessage = nil
        }
        
        deinit {
            networkMonitor.cancel()
        }
    }
