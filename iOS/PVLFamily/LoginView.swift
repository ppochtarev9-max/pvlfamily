import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var newName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                Text("PVLFamily")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
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
                
                Spacer()
            }
            .padding()
            .navigationTitle("Вход")
        }
    }
}
