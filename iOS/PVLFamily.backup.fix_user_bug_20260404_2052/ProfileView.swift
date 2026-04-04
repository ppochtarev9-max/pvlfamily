import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingDeleteAlert = false
    
    // Получаем ID текущего пользователя из токена (упрощенно)
    // В реальном проекте лучше декодировать JWT токен полностью
    var currentUserId: Int? {
        // Здесь можно распарсить токен, но пока предположим, что мы знаем ID
        // Или передадим его при логине в AuthManager
        // Для примера возьмем из users массива по имени
        if let name = authManager.userName,
           let user = authManager.users.first(where: { $0["name"] as? String == name }) {
            return user["id"] as? Int
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Пользователь")) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text(authManager.userName ?? "Гость")
                                .font(.headline)
                            Text("В системе")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Section {
                    Button("Выйти", role: .destructive) {
                        authManager.logout()
                    }
                }
                
                Section {
                    Button("Удалить аккаунт", role: .destructive) {
                        showingDeleteAlert = true
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Профиль")
            .alert("Удаление аккаунта", isPresented: $showingDeleteAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Удалить", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("Вы уверены? Все ваши транзакции и события календаря будут сохранены в истории, но станут «бесхозными». Это действие нельзя отменить.")
            }
        }
    }
    
    func performDelete() {
        guard let userId = currentUserId else {
            // Если не нашли ID, пробуем выйти просто так
            authManager.logout()
            return
        }
        
        authManager.deleteUser(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    authManager.logout() // Выход после успешного удаления
                case .failure(let error):
                    print("Ошибка удаления: \(error.localizedDescription)")
                    // Можно показать алерт об ошибке
                }
            }
        }
    }
}
