import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showingDeleteAlert = false
    
    // Состояния для категорий
    @State private var showingCategoriesManager = false
    @State private var categories: [BudgetView.Category] = []
    
    var currentUserId: Int? {
        if let name = authManager.userName,
           let user = authManager.users.first(where: { $0["name"] as? String == name }) {
            return user["id"] as? Int
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                // Секция профиля
                Section {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(authManager.userName ?? "Гость")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("В системе")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                }
                
                // Настройки (Новая секция)
                Section("Настройки") {
                    Button(action: {
                        loadCategories()
                        showingCategoriesManager = true
                    }) {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                            Text("Управление категориями")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
                
                // Действия
                Section {
                    Button(action: {
                        authManager.logout()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.orange)
                            Text("Выйти")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Действия")
                }
                
                Section {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                            Text("Удалить аккаунт")
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("При удалении аккаунта все ваши транзакции и события будут сохранены в истории, но станут «бесхозными».")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Профиль")
            // Выносим navigationDestination наружу из List, чтобы избежать ошибки SwiftUI
            .navigationDestination(isPresented: $showingCategoriesManager) {
                CategoriesManagerView(categories: $categories)
            }
            .alert("Удаление аккаунта", isPresented: $showingDeleteAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Удалить", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("Вы уверены? Это действие нельзя отменить.")
            }
        }
    }
    
    // Загрузка категорий перед открытием менеджера
    func loadCategories() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
            DispatchQueue.main.async { categories = list }
        }.resume()
    }
    
    func performDelete() {
        guard let userId = currentUserId else {
            authManager.logout()
            return
        }
        
        authManager.deleteUser(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    authManager.logout()
                case .failure(let error):
                    print("Ошибка удаления: \(error.localizedDescription)")
                }
            }
        }
    }
}
