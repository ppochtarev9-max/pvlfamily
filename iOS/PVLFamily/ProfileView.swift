import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Состояния UI
    @State private var showingDeleteAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var isDeleting = false
    
    // Состояния для категорий
    @State private var showingCategoriesManager = false
    @State private var categories: [BudgetView.Category] = []
    @State private var isLoadingCategories = false
    @State private var categoryLoadError: String?
    
    var currentUserId: Int? {
        if let name = authManager.userName,
           let user = authManager.users.first(where: { $0["name"] as? String == name }) {
            return user["id"] as? Int
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if isDeleting {
                    ProgressView("Удаление аккаунта...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
                        
                        // Настройки
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
                                    if isLoadingCategories {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                            }
                            .disabled(isLoadingCategories)
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
                                    if isDeleting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .disabled(isDeleting)
                        } footer: {
                            Text("При удалении аккаунта все ваши транзакции и события будут сохранены в истории, но станут «бесхозными».")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Профиль")
            .navigationDestination(isPresented: $showingCategoriesManager) {
                CategoriesManagerView(categories: $categories)
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .alert("Ошибка загрузки категорий", isPresented: .constant(categoryLoadError != nil)) {
                Button("OK") { categoryLoadError = nil }
            } message: {
                Text(categoryLoadError ?? "")
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
    
    // Загрузка категорий с обработкой ошибок
    func loadCategories() {
        guard let token = authManager.token else {
            categoryLoadError = "Пользователь не авторизован"
            return
        }
        
        isLoadingCategories = true
        categoryLoadError = nil
        
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoadingCategories = false
                
                if let error = error {
                    categoryLoadError = "Ошибка сети: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    categoryLoadError = "Ошибка сервера при загрузке категорий"
                    return
                }
                
                guard let data = data else {
                    categoryLoadError = "Пустой ответ от сервера"
                    return
                }
                
                do {
                    let list = try JSONDecoder().decode([BudgetView.Category].self, from: data)
                    self.categories = list
                } catch {
                    categoryLoadError = "Ошибка обработки данных: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func performDelete() {
        guard let userId = currentUserId else {
            errorMessage = "Не удалось определить ID пользователя"
            showErrorAlert = true
            authManager.logout()
            return
        }
        
        isDeleting = true
        errorMessage = nil
        
        authManager.deleteUser(userId: userId) { result in
            DispatchQueue.main.async {
                isDeleting = false
                
                switch result {
                case .success:
                    authManager.logout()
                case .failure(let error):
                    errorMessage = "Ошибка удаления: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
}
