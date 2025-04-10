//
//  PendingApprovalView.swift
//  BandSync
//
//  Created by Oleksandr Kuziakin on 10.04.2025.
//

import SwiftUI

struct PendingApprovalView: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.clock")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Ожидание подтверждения")
                .font(.title.bold())
            
            Text("Ваша заявка на вступление в группу ожидает подтверждения администратором.")
                .multilineTextAlignment(.center)
                .padding()
            
            Text("Пожалуйста, подождите или свяжитесь с администратором группы.")
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Выйти из аккаунта") {
                appState.logout()
            }
            .padding()
            .foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.9))
    }
}
