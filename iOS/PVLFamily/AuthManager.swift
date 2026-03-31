import Foundation
import Combine

class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userName: String?
    @Published var token: String?
    @Published var errorMessage: String?
    @Published var users: [[String: Any]] = []
    
    let baseURL = "http://127.0.0.1:8000"
    
    init() {
        loadStoredUser()
        loadUsers()
    }
    
    func loadStoredUser() {
        if let savedToken = UserDefaults.standard.string(forKey: "userToken"),
           let savedName = UserDefaults.standard.string(forKey: "userName") {
            self.token = savedToken
            self.userName = savedName
            self.isLoggedIn = true
        }
    }
    
    func loadUsers() {
        guard let url = URL(string: "\(baseURL)/auth/users") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            DispatchQueue.main.async {
                self.users = json
            }
        }.resume()
    }
    
    func login(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Введите имя"
            return
        }
        
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name])
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String,
                      let nameResp = json["name"] as? String else {
                    self.errorMessage = "Ошибка сервера"
                    return
                }
                
                self.token = accessToken
                self.userName = nameResp
                self.isLoggedIn = true
                self.errorMessage = nil
                
                UserDefaults.standard.set(accessToken, forKey: "userToken")
                UserDefaults.standard.set(nameResp, forKey: "userName")
                self.loadUsers()
            }
        }.resume()
    }
    
    func logout() {
        isLoggedIn = false
        userName = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: "userToken")
        UserDefaults.standard.removeObject(forKey: "userName")
    }
}
