import Foundation
import Combine

// --- МОДЕЛИ ОШИБОК ---
enum APIError: LocalizedError {
    case networkError(Error)
    case noData
    case decodingError(Error)
    case httpError(statusCode: Int, message: String)
    case invalidURL
    case unauthorized
    case serverError
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        case .noData:
            return "Нет данных от сервера"
        case .decodingError(let error):
            return "Ошибка формата данных: \(error.localizedDescription)"
        case .httpError(let code, let msg):
            if code == 400 { return "Неверные данные: \(msg)" }
            if code == 401 { return "Не авторизован: \(msg)" }
            if code == 404 { return "Не найдено: \(msg)" }
            if code >= 500 { return "Ошибка сервера (\(code)): \(msg)" }
            return "Ошибка HTTP \(code): \(msg)"
        case .invalidURL:
            return "Неверный URL"
        case .unauthorized:
            return "Сессия истекла. Войдите снова."
        case .serverError:
            return "Сервер временно недоступен"
        }
    }
}

// Режимы сервера
enum ServerMode { case local, cloud }

class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userName: String?
    @Published var token: String?
    @Published var userId: Int?
    @Published var errorMessage: String?
    @Published var users: [[String: Any]] = []
    
    @Published var selectedServer: ServerMode = .local
    var baseURL: String = "http://127.0.0.1:8000"
    
    // Конфигурация сессии
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10 // Таймаут запроса
        config.timeoutIntervalForResource = 30 // Таймаут ресурса
        return URLSession(configuration: config)
    }()
    
    init() {
        updateBaseURL()
        loadStoredUser()
        loadUsers()
    }
    
    func updateBaseURL() {
        switch selectedServer {
        case .local: self.baseURL = "http://127.0.0.1:8000"
        case .cloud: self.baseURL = "http://213.171.28.80:8000"
        }
        print("🌐 Сервер переключен на: \(baseURL)")
    }
    
    // --- ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ---
    
    /// Проверяет HTTP статус и возвращает понятную ошибку
    private func handleHTTPResponse(_ response: URLResponse?, data: Data?) -> Result<Void, APIError> {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.serverError)
        }
        
        // Успешные коды 2xx
        if (200...299).contains(httpResponse.statusCode) {
            return .success(())
        }
        
        // Попытка распарсить сообщение об ошибке из тела ответа
        var errorMsg = "Неизвестная ошибка"
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            errorMsg = detail
        } else if let data = data, let str = String(data: data, encoding: .utf8) {
            errorMsg = str
        }
        
        print("❌ HTTP Error \(httpResponse.statusCode): \(errorMsg)")
        
        if httpResponse.statusCode == 401 {
            return .failure(.unauthorized)
        }
        
        return .failure(.httpError(statusCode: httpResponse.statusCode, message: errorMsg))
    }
    
    // --- ОСНОВНЫЕ МЕТОДЫ ---
    
    func loadStoredUser() {
        if let savedToken = UserDefaults.standard.string(forKey: "userToken"),
           let savedName = UserDefaults.standard.string(forKey: "userName") {
            
            let hasIdKey = UserDefaults.standard.object(forKey: "userId") != nil
            let savedId = UserDefaults.standard.integer(forKey: "userId")
            
            if hasIdKey && savedId != 0 {
                self.token = savedToken
                self.userName = savedName
                self.userId = savedId
                self.isLoggedIn = true
                print("🔄 ВОССТАНОВЛЕН ПОЛЬЗОВАТЕЛЬ: \(savedName) (ID: \(savedId))")
            } else {
                print("⚠️ Найден токен, но нет ID. Выполняется выход.")
                self.logout()
            }
        }
    }
    
    func loadUsers() {
        guard let url = URL(string: "\(baseURL)/auth/users") else {
            print("❌ Ошибка URL при загрузке пользователей")
            return
        }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Ошибка сети при загрузке пользователей: \(error)")
                    self.errorMessage = APIError.networkError(error).errorDescription
                    return
                }
                
                // Проверка статуса
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                        print("❌ Ошибка декодирования пользователей")
                        return
                    }
                    self.users = json
                case .failure(let apiError):
                    self.errorMessage = apiError.errorDescription
                }
            }
        }.resume()
    }
    
    func login(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Введите имя"
            return
        }
        
        guard let url = URL(string: "\(baseURL)/auth/login") else {
            errorMessage = APIError.invalidURL.errorDescription
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
        } catch {
            errorMessage = "Ошибка формирования запроса"
            return
        }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // 1. Ошибка сети
                if let error = error {
                    self.errorMessage = APIError.networkError(error).errorDescription
                    print("❌ Network error: \(error)")
                    return
                }
                
                // 2. Проверка HTTP статуса
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    guard let data = data else {
                        self.errorMessage = APIError.noData.errorDescription
                        return
                    }
                    
                    // 3. Парсинг ответа
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let accessToken = json["access_token"] as? String,
                              let nameResp = json["name"] as? String,
                              let userId = json["user_id"] as? Int else {
                            throw APIError.decodingError(NSError(domain: "JSON", code: -1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат ответа"]))
                        }
                        
                        self.token = accessToken
                        self.userName = nameResp
                        self.userId = userId
                        self.isLoggedIn = true
                        self.errorMessage = nil
                        
                        UserDefaults.standard.set(accessToken, forKey: "userToken")
                        UserDefaults.standard.set(nameResp, forKey: "userName")
                        UserDefaults.standard.set(userId, forKey: "userId")
                        
                        print("✅ ВХОД ВЫПОЛНЕН: \(nameResp) (ID: \(userId))")
                        self.loadUsers()
                        
                    } catch {
                        self.errorMessage = APIError.decodingError(error).errorDescription
                        print("❌ Decoding error: \(error)")
                    }
                    
                case .failure(let apiError):
                    self.errorMessage = apiError.errorDescription
                }
            }
        }.resume()
    }
    
    func logout() {
        isLoggedIn = false
        userName = nil
        userId = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: "userToken")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userId")
        print("🚪 ПОЛЬЗОВАТЕЛЬ ВЫШЕЛ")
    }
    
    func deleteUser(userId: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = token else {
            completion(.failure(APIError.unauthorized))
            return
        }
        
        guard let url = URL(string: "\(baseURL)/auth/users/\(userId)") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        
        session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(APIError.networkError(error)))
                return
            }
            
            switch self.handleHTTPResponse(response, data: data) {
            case .success:
                completion(.success(()))
            case .failure(let apiError):
                completion(.failure(apiError))
            }
        }.resume()
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
            completion(.failure(APIError.unauthorized))
            return
        }
        
        var components = URLComponents(string: baseURL + endpoint)
        if !queryParams.isEmpty {
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let url = components?.url else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        
        session.dataTask(with: req) { data, resp, err in
            // 1. Сетевая ошибка
            if let err = err {
                completion(.failure(APIError.networkError(err)))
                return
            }
            
            // 2. HTTP статус
            switch self.handleHTTPResponse(resp, data: data) {
            case .success:
                guard let data = data else {
                    completion(.failure(APIError.noData))
                    return
                }
                
                // 3. Декодирование
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(APIError.decodingError(error)))
                }
                
            case .failure(let apiError):
                completion(.failure(apiError))
            }
        }.resume()
    }
}
