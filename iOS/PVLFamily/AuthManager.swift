import Foundation
import Combine

class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userName: String?
    @Published var token: String?
    @Published var errorMessage: String?
    @Published var users: [[String: Any]] = []
    
    @Published var baseURL: String = "http://127.0.0.1:8000"
    //let baseURL = "http://213.171.28.80:8000"
    //let baseURL = "http://127.0.0.1:8000"
    
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

    func setServer(_ url: String) {
         self.baseURL = url
         self.users = [] // Сбрасываем список пользователей при смене сервера
         loadUsers() // Загружаем пользователей с нового сервера
     }

}


// MARK: - Dashboard Models
struct DashboardSummary: Codable {
    let balance: Double
    let total_income: Double
    let total_expense: Double
}

struct MonthlyStatDetail: Codable {
    let category_id: Int?
    let category_name: String
    let type: String
    let amount: Double
}

struct MonthlyStats: Codable {
    let year: Int
    let month: Int
    let total_income: Double
    let total_expense: Double
    let balance: Double
    let details: [MonthlyStatDetail]
}

// MARK: - Dashboard API Methods
extension AuthManager {
    func getDashboardSummary(asOfDate: String?, userId: Int?, completion: @escaping (Result<DashboardSummary, Error>) -> Void) {
        var params: [String: String] = [:]
        if let date = asOfDate { params["as_of_date"] = date }
        if let uid = userId { params["user_id"] = "\(uid)" }
        
        request(endpoint: "/dashboard/summary", method: "GET", queryParams: params, completion: completion)
    }
    
    func getMonthlyStats(year: Int, month: Int, userId: Int?, completion: @escaping (Result<MonthlyStats, Error>) -> Void) {
        var params: [String: String] = [
            "year": "\(year)",
            "month": "\(month)"
        ]
        if let uid = userId { params["user_id"] = "\(uid)" }
        
        request(endpoint: "/dashboard/monthly-stats", method: "GET", queryParams: params, completion: completion)
    }
    
    private func request<T: Codable>(endpoint: String, method: String, queryParams: [String: String] = [:], completion: @escaping (Result<T, Error>) -> Void) {
        guard let token = token else {
            completion(.failure(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Token missing"])))
            return
        }
        
        var components = URLComponents(string: baseURL + endpoint)
        if !queryParams.isEmpty {
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "URL", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                completion(.failure(err))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "Data", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
