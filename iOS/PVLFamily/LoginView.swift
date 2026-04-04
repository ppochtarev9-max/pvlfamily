import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var newName: String = ""
    
    // Состояния для выбора сервера
    @State private var showServerSelection = true
    @State private var selectedServer: String = "http://127.0.0.1:8000" // По умолчанию локальный
    @State private var customServerURL: String = ""
    
    let servers = [
        "Локальный (Mac)": "http://127.0.0.1:8000",
        "Облако (Cloud.ru)": "http://213.171.28.80:8000"
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Ваша кастомная картинка
                // Замените "LaunchImage" на имя вашей картинки в Assets.xcassets
                Image("Leo") 
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                    .cornerRadius(20)
                    .shadow(radius: 10)
                
                Text("PVLFamily")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                // Экран выбора сервера
                if showServerSelection {
                    VStack(spacing: 15) {
                        Text("Выберите сервер подключения:")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Picker("Сервер", selection: $selectedServer) {
                            ForEach(servers.keys.sorted(), id: \.self) { key in
                                Text(key).tag(servers[key] ?? "")
                            }
                            Text("Свой...").tag("custom")
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        if selectedServer == "custom" {
                            TextField("Введите URL (например, http://192.168.1.5:8000)", text: $customServerURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .padding(.horizontal)
                        }
                        
                        Button(action: confirmServerSelection) {
                            Text("Подключиться")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .disabled(selectedServer == "custom" && customServerURL.isEmpty)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(15)
                    .padding(.horizontal)
                } else {
                    // Стандартный экран входа (показывается после выбора сервера)
                    if !authManager.users.isEmpty {
                        Text("Выберите пользователя:")
                            .font(.headline)
                            .padding(.top)
                        
                        List(0..<authManager.users.count, id: \.self) { index in
                            let user = authManager.users[index]
                            Button(action: {
                                if let name = user["name"] as? String {
                                    authManager.login(name: name)
                                }
                            }) {
                                HStack {
                                    Image(systemName: "person.circle")
                                    Text(user["name"] as? String ?? "Unknown")
                                }
                            }
                        }
                        .frame(height: 200)
                    }
                    
                    Divider()
                    
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
                        Text(error).foregroundColor(.red).font(.caption)
                    }
                }
                
                Spacer()
                
                // Кнопка смены сервера (если уже выбран)
                if !showServerSelection {
                    Button("Сменить сервер") {
                        showServerSelection = true
                        authManager.logout() // Выходим при смене сервера
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.bottom, 20)
                }
            }
            .padding()
            .navigationTitle(showServerSelection ? "Настройки сервера" : "Вход")
        }
    }
    
    func confirmServerSelection() {
        let finalURL = (selectedServer == "custom") ? customServerURL : selectedServer
        authManager.setServer(finalURL)
        withAnimation {
            showServerSelection = false
        }
    }
}
