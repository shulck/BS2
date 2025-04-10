//
//  CacheSettingsView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 31.03.2025.
//


//
//  CacheSettingsView.swift
//  BandSync
//
//  Created by Claude AI on 31.03.2025.
//

import SwiftUI

struct CacheSettingsView: View {
    @State private var cacheInfo: [String: Any] = [:]
    @State private var isClearing = false
    @State private var showClearConfirmation = false
    
    var body: some View {
        List {
            Section(header: Text("Cache Information".localized)) {
                // Total cache size
                HStack {
                    Text("Total Size".localized)
                    Spacer()
                    Text(formattedSize)
                        .foregroundColor(.secondary)
                }
                
                // Number of files
                HStack {
                    Text("Files".localized)
                    Spacer()
                    Text("\(fileCount)")
                        .foregroundColor(.secondary)
                }
                
                // Oldest cache date
                HStack {
                    Text("Oldest Cache".localized)
                    Spacer()
                    Text(formattedOldestDate)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                // Clear cache button
                Button(action: {
                    showClearConfirmation = true
                }) {
                    HStack {
                        Text("Clear Cache".localized)
                        Spacer()
                        if isClearing {
                            ProgressView()
                        }
                    }
                    .foregroundColor(.red)
                }
                .disabled(isClearing)
                
                // Clear old cache button
                Button(action: {
                    clearOldCache()
                }) {
                    Text("Clear Older Than 30 Days".localized)
                }
                .disabled(isClearing)
            }
        }
        .navigationTitle("Cache Settings".localized)
        .onAppear {
            loadCacheInfo()
        }
        .alert(isPresented: $showClearConfirmation) {
            Alert(
                title: Text("Clear Cache?".localized),
                message: Text("This will delete all cached data. The app will download fresh data when online.".localized),
                primaryButton: .destructive(Text("Clear".localized)) {
                    clearAllCache()
                },
                secondaryButton: .cancel()
            )
        }
        .refreshable {
            loadCacheInfo()
        }
    }
    
    // Load cache information
    private func loadCacheInfo() {
        cacheInfo = CacheService.shared.getCacheInfo()
    }
    
    // Clear all cache
    private func clearAllCache() {
        isClearing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            CacheService.shared.clearAllCache()
            
            DispatchQueue.main.async {
                isClearing = false
                loadCacheInfo()
            }
        }
    }
    
    // Clear old cache
    private func clearOldCache() {
        isClearing = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            CacheService.shared.clearOldCache()
            
            DispatchQueue.main.async {
                isClearing = false
                loadCacheInfo()
            }
        }
    }
    
    // Formatted cache size
    private var formattedSize: String {
        let size = cacheInfo["totalSize"] as? UInt64 ?? 0
        
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
    
    // File count
    private var fileCount: Int {
        return cacheInfo["fileCount"] as? Int ?? 0
    }
    
    // Formatted oldest cache date
    private var formattedOldestDate: String {
        guard let date = cacheInfo["oldestCache"] as? Date else {
            return "—"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
