import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var newName: String = ""
    @State private var isAnimating: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Фон с градиентом
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.systemGray6)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        Spacer(minLength: 40)
                        
                        // Картинка
                        Image("Leo")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 400)
                            .clipped()
                            .shadow(color: Color.blue.opacity(0.3), radius: 20, x: 0, y: 10)
                            .opacity(isAnimating ? 1.0 : 0.0) // Только прозрачность
                            .animation(.easeInOut(duration: 1.0), value: isAnimating) // Плавное затухание
                        
                        // Заголовок
                        VStack(spacing: 8) {
                            Text("PVLFamily")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("Учет финансов семьи")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut.delay(0.3), value: isAnimating)
                        
                        // Выбор сервера
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Режим работы")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            Picker("Сервер", selection: $authManager.selectedServer) {
                                Text("Локальный").tag(ServerMode.local)
                                Text("Облако").tag(ServerMode.cloud)
                            }
                            .pickerStyle(.segmented)
                            .padding(4)
                            .background(Color(.systemGray5))
                            .cornerRadius(12)
                            .onChange(of: authManager.selectedServer) { _, _ in
                                authManager.updateBaseURL()
                                authManager.loadUsers()
                            }
                        }
                        .padding(.horizontal)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut.delay(0.5), value: isAnimating)
                        
                        // Список пользователей
                        if !authManager.users.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Быстрый вход")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                
                                VStack(spacing: 8) {
                                    // ИСПРАВЛЕНО: используем indices и безопасное получение данных
                                    ForEach(authManager.users.indices, id: \.self) { index in
                                        let user = authManager.users[index]
                                        if let name = user["name"] as? String {
                                            Button(action: {
                                                withAnimation {
                                                    authManager.login(name: name)
                                                }
                                            }) {
                                                HStack {
                                                    Circle()
                                                        .fill(Color.blue.opacity(0.1))
                                                        .frame(width: 40, height: 40)
                                                        .overlay(
                                                            Image(systemName: "person.fill")
                                                                .foregroundColor(.blue)
                                                        )
                                                    
                                                    Text(name)
                                                        .font(.body)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.primary)
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: "chevron.right")
                                                        .foregroundColor(.gray)
                                                }
                                                .padding()
                                                .background(Color(.systemBackground))
                                                .cornerRadius(16)
                                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .opacity(isAnimating ? 1.0 : 0.0)
                            .animation(.easeInOut.delay(0.7), value: isAnimating)
                        }
                        
                        Divider()
                            .padding(.horizontal)
                            .opacity(isAnimating ? 1.0 : 0.0)
                        
                        // Создание нового пользователя
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Новый пользователь")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            HStack(spacing: 12) {
                                TextField("Введите имя", text: $newName)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                
                                Button(action: {
                                    withAnimation {
                                        authManager.login(name: newName)
                                    }
                                }) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(newName.isEmpty ? .gray : .blue)
                                }
                                .disabled(newName.isEmpty)
                            }
                        }
                        .padding(.horizontal)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut.delay(0.9), value: isAnimating)
                        
                        // Ошибка
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red)
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .onAppear {
                isAnimating = true
            }
        }
    }
}
