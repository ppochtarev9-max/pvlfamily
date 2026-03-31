import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationView {
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
            }
            .navigationTitle("Профиль")
        }
    }
}
