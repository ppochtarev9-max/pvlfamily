import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var userName: String = ""
    @State private var password: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
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
                            .shadow(color: FamilyAppStyle.accent.opacity(0.3), radius: 20, x: 0, y: 10)
                            .opacity(isAnimating ? 1.0 : 0.0) // Только прозрачность
                            .animation(.easeInOut(duration: 1.0), value: isAnimating) // Плавное затухание
                        
                        // Заголовок
                        VStack(spacing: 8) {
                            Text("PVLFamily")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            //Text("Учет финансов семьи")
                            //    .font(.subheadline)
                            //    .foregroundColor(.secondary)
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
                            .tint(FamilyAppStyle.accent)
                            .onChange(of: authManager.selectedServer) { _, _ in
                                authManager.updateBaseURL()
                                authManager.loadUsers()
                            }
                        }
                        .padding(.horizontal)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut.delay(0.5), value: isAnimating)

                        Divider()
                            .padding(.horizontal)
                            .opacity(isAnimating ? 1.0 : 0.0)
                        
                        // Логин
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Вход")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 12) {
                                TextField("Введите имя", text: $userName)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(FamilyAppStyle.listCardFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
                                    )
                                    .accessibilityIdentifier("NameInput")

                                SecureField("Введите пароль", text: $password)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(FamilyAppStyle.listCardFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
                                    )
                                    .accessibilityIdentifier("PasswordInput")

                                Button(action: {
                                    withAnimation {
                                        authManager.login(name: userName, password: password)
                                    }
                                }) {
                                    Text("Войти")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background((userName.isEmpty || password.isEmpty) ? Color.gray : FamilyAppStyle.accent)
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .disabled(userName.isEmpty || password.isEmpty)
                                .accessibilityIdentifier("LoginButton")
                            }
                        }
                        .padding(.horizontal)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .animation(.easeInOut.delay(0.9), value: isAnimating)

                        if authManager.requiresPasswordReset {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Смена временного пароля")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                SecureField("Новый пароль (минимум 8 символов)", text: $newPassword)
                                    .textFieldStyle(.roundedBorder)
                                SecureField("Повторите новый пароль", text: $confirmPassword)
                                    .textFieldStyle(.roundedBorder)
                                Button("Сохранить новый пароль") {
                                    guard newPassword == confirmPassword else {
                                        authManager.errorMessage = "Пароли не совпадают"
                                        return
                                    }
                                    authManager.changePassword(newPassword: newPassword) { result in
                                        switch result {
                                        case .success:
                                            authManager.errorMessage = "Пароль обновлен. Выполните вход заново."
                                            password = ""
                                            newPassword = ""
                                            confirmPassword = ""
                                        case .failure(let error):
                                            authManager.errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newPassword.count < 8 || confirmPassword.isEmpty)
                            }
                            .padding(.horizontal)
                        }
                        
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
            .tint(FamilyAppStyle.accent)
            .onAppear {
                isAnimating = true
            }
        }
    }
}
