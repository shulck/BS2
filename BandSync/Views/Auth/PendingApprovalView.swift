// PendingApprovalView.swift - улучшенная версия
import SwiftUI
import FirebaseFirestore

struct PendingApprovalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLeaveConfirmation = false
    
    var body: some View {
        VStack(spacing: 30) {
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
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button("Отменить запрос и выйти из группы") {
                showLeaveConfirmation = true
            }
            .padding()
            .foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(isPresented: $showLeaveConfirmation) {
            Alert(
                title: Text("Отменить запрос"),
                message: Text("Вы действительно хотите отменить запрос на вступление в группу?"),
                primaryButton: .destructive(Text("Да, отменить")) {
                    cancelRequest()
                },
                secondaryButton: .cancel(Text("Нет"))
            )
        }
    }
    
    private func cancelRequest() {
        if let userId = appState.user?.id,
           let groupId = appState.user?.groupId {
            
            let db = FirebaseFirestore.Firestore.firestore()
            
            // Удаляем пользователя из списка ожидающих в группе
            db.collection("groups").document(groupId).updateData([
                "pendingMembers": FirebaseFirestore.FieldValue.arrayRemove([userId])
            ])
            
            // Удаляем groupId у пользователя
            db.collection("users").document(userId).updateData([
                "groupId": FirebaseFirestore.FieldValue.delete()
            ]) { _ in
                // Обновляем состояние приложения
                appState.refreshAuthState()
            }
        }
    }
}
