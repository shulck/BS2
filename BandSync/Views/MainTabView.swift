import SwiftUI

struct MainTabView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var permissionService = PermissionService.shared
    @State private var selectedTab = 0
    @State private var showMoreMenu = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Main tabs (always visible)
            
            // 1. Calendar
            if permissionService.currentUserHasAccess(to: .calendar) {
                CalendarView()
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(0)
            }
            
            // 2. Finances
            if permissionService.currentUserHasAccess(to: .finances) {
                FinancesView()
                    .tabItem {
                        Label("Finances", systemImage: "dollarsign.circle")
                    }
                    .tag(1)
            }
            
            // 3. Merch
            if permissionService.currentUserHasAccess(to: .merchandise) {
                MerchView()
                    .tabItem {
                        Label("Merch", systemImage: "bag")
                    }
                    .tag(2)
            }
            
            // 4. Chats
            if permissionService.currentUserHasAccess(to: .chats) {
                ChatsView()
                    .tabItem {
                        Label("Chats", systemImage: "message")
                    }
                    .tag(3)
            }
            
            // 5. More
            MoreMenuView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(4)
        }
        .onAppear {
            appState.refreshAuthState()
            
            // If the current tab is unavailable, switch to the first available one
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                ensureValidTab()
            }
        }
        .onChange(of: permissionService.permissions) { _ in
            // When permissions change, check that the current tab is available
            ensureValidTab()
        }
    }
    
    // Ensures that an accessible tab is selected
    private func ensureValidTab() {
        let modules = permissionService.getCurrentUserAccessibleModules()
        
        // Check if user has access to the current tab
        var isCurrentTabAccessible = false
        
        switch selectedTab {
        case 0: isCurrentTabAccessible = modules.contains(.calendar)
        case 1: isCurrentTabAccessible = modules.contains(.finances)
        case 2: isCurrentTabAccessible = modules.contains(.merchandise)
        case 3: isCurrentTabAccessible = modules.contains(.chats)
        case 4: isCurrentTabAccessible = true // More menu always available
        default: isCurrentTabAccessible = false
        }
        
        // If current tab is inaccessible, select the first available one
        if !isCurrentTabAccessible {
            // By default, the More tab should always be accessible
            selectedTab = 4
            
            // Check availability of other tabs by priority
            if modules.contains(.calendar) {
                selectedTab = 0
            } else if modules.contains(.finances) {
                selectedTab = 1
            } else if modules.contains(.merchandise) {
                selectedTab = 2
            } else if modules.contains(.chats) {
                selectedTab = 3
            }
        }
    }
}

// View for the "More" menu
struct MoreMenuView: View {
    @StateObject private var permissionService = PermissionService.shared
    @State private var selectedOption: String? = nil
    
    var body: some View {
        NavigationView {
            List {
                // Setlists
                if permissionService.currentUserHasAccess(to: .setlists) {
                    NavigationLink(destination: SetlistView()) {
                        Label("Setlists", systemImage: "music.note.list")
                    }
                }
                
                // Tasks
                if permissionService.currentUserHasAccess(to: .tasks) {
                    NavigationLink(destination: TasksView()) {
                        Label("Tasks", systemImage: "checklist")
                    }
                }
                
                // Contacts
                if permissionService.currentUserHasAccess(to: .contacts) {
                    NavigationLink(destination: ContactsView()) {
                        Label("Contacts", systemImage: "person.crop.circle")
                    }
                }
                
                // Settings (available to everyone)
                NavigationLink(destination: SettingsView()) {
                    Label("Settings", systemImage: "gear")
                }
                
                // Admin panel
                if permissionService.currentUserHasAccess(to: .admin) {
                    NavigationLink(destination: AdminPanelView()) {
                        Label("Admin", systemImage: "person.3")
                    }
                }
            }
            .navigationTitle("More")
            .listStyle(InsetGroupedListStyle())
        }
    }
}
