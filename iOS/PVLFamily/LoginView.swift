import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var newName: String = ""
    
    // Опции серверов
    enum ServerOption: String, CaseIterable {
        case local = "Локальный (Mac)"
        case cloud = "Облако (Cloud.ru)"
        
        var url: String {
            switch self {
            case .local: return "http://127.0.0.1:8000"
            case .cloud: return "http://213.171.28.80:8000"
            }
        }
    }
    
    @State private var selectedServer: ServerOption = .local

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Логотип
                Image("Leo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                
                Text("PVLFamily")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Выбор сервера
                VStack(alignment: .leading, spacing: 8) {
                    Text("Сервер:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Выберите сервер", selection: $selectedServer) {
                        ForEach(ServerOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu) // Выпадающий список
                    .buttonStyle(.bordered)
                    .onChange(of: selectedServer) { newValue in
                        authManager.baseURL = newValue.url
                        // При смене сервера перезагружаем список пользователей
                        authManager.loadUsers()
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Список пользователей
                if !authManager.users.isEmpty {
                    Text("Выберите пользователя:")
                        .font(.headline)
                    
                    List(0..<authManager.users.count, id: \.self) { index in
                        let user = authManager.users[index]
                        Button(action: {
                            if let name = user["name"] as? String {
                                authManager.login(name: name)
                            }
                        }) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundColor(.blue)
                                Text(user["name"] as? String ?? "Unknown")
                            }
                        }
                    }
                    .frame(height: 200)
                } else {
                    ProgressView("Загрузка пользователей...")
                        .padding()
                }
                
                Divider()
                
                // Новый пользователь
                Text("Или создайте нового:")
                    .font(.headline)
                
                HStack {
                    TextField("Имя", text: $newName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Войти") {
                        authManager.login(name: newName)
                    }
                    .disabled(newName.isEmpty)
                }
                
                if let error = authManager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Вход")
        }
    }
}
