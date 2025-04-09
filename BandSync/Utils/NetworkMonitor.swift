//
//  NetworkMonitor.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 09.04.2025.
//


//
//  NetworkMonitor.swift
//  BandSync
//
//  Created by Claude AI on 09.04.2025.
//

import Foundation
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        print("NetworkMonitor: initialized")
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                print("NetworkMonitor: connection status changed - connected: \(path.status == .satisfied)")
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
        print("NetworkMonitor: cancelled")
    }
    
    func startMonitoring() {
        // This is a no-op as monitoring starts at initialization,
        // but can be used to restart monitoring if needed
        if monitor.queue == nil {
            monitor.start(queue: queue)
            print("NetworkMonitor: monitoring started")
        }
    }
    
    func stopMonitoring() {
        monitor.cancel()
        print("NetworkMonitor: monitoring stopped")
    }
}