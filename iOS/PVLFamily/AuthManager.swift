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
        case .networkError(let error): return "Ошибка сети: \(error.localizedDescription)"
        case .noData: return "Нет данных от сервера"
        case .decodingError(let error): return "Ошибка формата: \(error.localizedDescription)"
        case .httpError(let code, let msg):
            if code == 400 { return "Неверные данные: \(msg)" }
            if code == 401 { return "Не авторизован: \(msg)" }
            if code == 404 { return "Не найдено: \(msg)" }
            if code >= 500 { return "Ошибка сервера (\(code)): \(msg)" }
            return "Ошибка HTTP \(code): \(msg)"
        case .invalidURL: return "Неверный URL"
        case .unauthorized: return "Сессия истекла."
        case .serverError: return "Сервер недоступен"
        }
    }
}

enum ServerMode { case local, cloud }

class AuthManager: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var userName: String?
    @Published var token: String?
    @Published var userId: Int?
    @Published var errorMessage: String?
    @Published var users: [[String: Any]] = []
    
    @Published var selectedServer: ServerMode {
         didSet {
             // Сохраняем выбор сразу при изменении
             let rawValue = selectedServer == .cloud ? "cloud" : "local"
             UserDefaults.standard.set(rawValue, forKey: "savedServerMode")
             updateBaseURL()
         }
     }

    var baseURL: String = "http://127.0.0.1:8000"
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
    
    init() {
        // 1. Проверяем, есть ли сохраненный выбор пользователя
        let savedMode = UserDefaults.standard.string(forKey: "savedServerMode")
        
        if savedMode == "cloud" {
            self.selectedServer = .cloud
            print("🌐 [CONFIG] Восстановлен режим: Cloud (из настроек)")
        } else if savedMode == "local" {
            self.selectedServer = .local
            print("🏠 [CONFIG] Восстановлен режим: Local (из настроек)")
        } else {
            // 2. Если настройки нет (первый запуск), определяем автоматически
            #if targetEnvironment(simulator)
                self.selectedServer = .local
                print("📱 [CONFIG] Запуск на СИМУЛЯТОРЕ. По умолчанию выбран LOCAL.")
            #else
                self.selectedServer = .cloud
                print("📲 [CONFIG] Запуск на УСТРОЙСТВЕ. По умолчанию выбран CLOUD.")
            #endif
            
            // Сохраняем этот выбор, чтобы не определять каждый раз
            let rawValue = selectedServer == .cloud ? "cloud" : "local"
            UserDefaults.standard.set(rawValue, forKey: "savedServerMode")
        }
        
        updateBaseURL()
        loadStoredUser()
        loadUsers()
    }

    static func resolvedBaseURL(for mode: ServerMode) -> String {
        switch mode {
        case .local:
            return "http://127.0.0.1:8000"
        case .cloud:
            return "https://pvlfamily.ru"
        }
    }

    static func apiErrorMessage(from data: Data?) -> String {
        var errorMsg = "Неизвестная ошибка"
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = json["detail"] as? String {
            errorMsg = detail
        } else if let data = data, let str = String(data: data, encoding: .utf8) {
            errorMsg = str
        }
        return errorMsg
    }
    
    func updateBaseURL() {
        self.baseURL = Self.resolvedBaseURL(for: selectedServer)
        print("🌐 Сервер: \(baseURL)")
    }
    
    private func handleHTTPResponse(_ response: URLResponse?, data: Data?) -> Result<Void, APIError> {
        guard let httpResponse = response as? HTTPURLResponse else { return .failure(.serverError) }
        if (200...299).contains(httpResponse.statusCode) { return .success(()) }

        let errorMsg = Self.apiErrorMessage(from: data)
        if httpResponse.statusCode == 401 { return .failure(.unauthorized) }
        return .failure(.httpError(statusCode: httpResponse.statusCode, message: errorMsg))
    }
    
    func loadStoredUser() {
        print("🔑 [AUTH] Попытка восстановления сессии...")
    
        let savedToken = UserDefaults.standard.string(forKey: "userToken")
        let savedName = UserDefaults.standard.string(forKey: "userName")
        let savedId = UserDefaults.standard.integer(forKey: "userId")
        let hasIdKey = UserDefaults.standard.object(forKey: "userId") != nil
        
        print("🔑 [AUTH] Token: \(savedToken != nil ? "Есть" : "Нет")")
        print("🔑 TOKEN VALUE: \(savedToken)")
        print("🔑 [AUTH] Name: \(savedName ?? "Нет")")
        print("🔑 [AUTH] ID: \(hasIdKey ? String(savedId) : "Не задан")")
        
        if let token = savedToken, let name = savedName {
            if hasIdKey && savedId != 0 {
                self.token = token
                self.userName = name
                self.userId = savedId
                self.isLoggedIn = true
                print("✅ [AUTH] Сессия восстановлена успешно: \(name)")
            } else {
                print("⚠️ [AUTH] Сессия неполная (нет ID или ID=0). Выполняем выход.")
                logout() // Здесь и происходит сброс, если ID потерян
            }
        } else {
            print("ℹ️ [AUTH] Данные не найдены. Пользователь гость.")
        }
    }
    
    func loadUsers() {
        guard let url = URL(string: "\(baseURL)/auth/users") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 10
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.errorMessage = APIError.networkError(error).errorDescription; return }
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.users = json
                    }
                case .failure(let apiError): self.errorMessage = apiError.errorDescription
                }
            }
        }.resume()
    }
    
    func login(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Введите имя"; return }
        guard let url = URL(string: "\(baseURL)/auth/login") else { errorMessage = APIError.invalidURL.errorDescription; return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        do { request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name]) }
        catch { errorMessage = "Ошибка формирования запроса"; return }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.errorMessage = APIError.networkError(error).errorDescription; return }
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    guard let data = data else { self.errorMessage = APIError.noData.errorDescription; return }
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let accessToken = json["access_token"] as? String,
                              let nameResp = json["name"] as? String,
                              let userId = json["user_id"] as? Int else {
                            throw APIError.decodingError(NSError(domain: "JSON", code: -1, userInfo: [:]))
                        }
                        self.token = accessToken; self.userName = nameResp; self.userId = userId; self.isLoggedIn = true; self.errorMessage = nil
                        UserDefaults.standard.set(accessToken, forKey: "userToken")
                        UserDefaults.standard.set(nameResp, forKey: "userName")
                        UserDefaults.standard.set(userId, forKey: "userId")
                        print("✅ Вход: \(nameResp)")
                        self.loadUsers()
                    } catch { self.errorMessage = APIError.decodingError(error).errorDescription }
                case .failure(let apiError): self.errorMessage = apiError.errorDescription
                }
            }
        }.resume()
    }
    
    func logout() {
        isLoggedIn = false; userName = nil; userId = nil; token = nil
        UserDefaults.standard.removeObject(forKey: "userToken")
        UserDefaults.standard.removeObject(forKey: "userName")
        UserDefaults.standard.removeObject(forKey: "userId")
        print("🚪 Выход")
    }
    
    func deleteUser(userId: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/auth/users/\(userId)") else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        session.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(APIError.networkError(error))); return }
            switch self.handleHTTPResponse(response, data: data) {
            case .success: completion(.success(()))
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }
}

// MARK: - Dashboard Models
struct DashboardSummary: Codable { let balance: Double; let total_income: Double; let total_expense: Double }
struct MonthlyStatDetail: Codable { let category_id: Int?; let category_name: String; let type: String; let amount: Double }
struct MonthlyStats: Codable {
    let year: Int; let month: Int; let total_income: Double; let total_expense: Double; let balance: Double; let details: [MonthlyStatDetail]
}

// MARK: - Tracker Models (НОВЫЕ)
struct TrackerStatus: Codable {
    let is_sleeping: Bool
    let current_sleep_id: Int?       // <-- Обязательно добавь это поле
    let current_sleep_start: String? // ISO8601 строка
    let last_wake_up: String?        // ISO8601 строка
}

// MARK: - API Methods Extension
extension AuthManager {
    // --- Dashboard ---
    func getDashboardSummary(asOfDate: String?, userId: Int?, completion: @escaping (Result<DashboardSummary, Error>) -> Void) {
        var params: [String: String] = [:]
        if let date = asOfDate { params["as_of_date"] = date }
        if let uid = userId { params["user_id"] = "\(uid)" }
        request(endpoint: "/dashboard/summary", method: "GET", queryParams: params, completion: completion)
    }
    
    func getMonthlyStats(year: Int, month: Int, userId: Int?, completion: @escaping (Result<MonthlyStats, Error>) -> Void) {
        var params: [String: String] = ["year": "\(year)", "month": "\(month)"]
        if let uid = userId { params["user_id"] = "\(uid)" }
        request(endpoint: "/dashboard/monthly-stats", method: "GET", queryParams: params, completion: completion)
    }
    
    // --- Tracker API ---
    func getTrackerStatus(completion: @escaping (Result<TrackerStatus, Error>) -> Void) {
        request(endpoint: "/tracker/status", method: "GET", completion: completion)
    }
    
    func startSleep(completion: @escaping (Result<TrackerStatus, Error>) -> Void) {
        // POST /tracker/logs с типом sleep и текущим временем
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = ["event_type": "sleep", "start_time": now]
        postLog(body: body, completion: completion)
    }
    
    func finishSleep(sleepId: Int, completion: @escaping (Result<TrackerStatus, Error>) -> Void) {
        // PUT /tracker/logs/{id} с end_time = now
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = ["end_time": now]
        
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/tracker/logs/\(sleepId)") else { completion(.failure(APIError.invalidURL)); return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(APIError.networkError(err))); return }
            switch self.handleHTTPResponse(resp, data: data) {
            case .success:
                // После обновления снова запрашиваем статус
                self.getTrackerStatus(completion: completion)
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }
    
    func quickFeed(completion: @escaping (Result<TrackerStatus, Error>) -> Void) {
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = ["event_type": "feed", "start_time": now, "end_time": now]
        postLog(body: body, completion: completion)
    }
    
    // Вспомогательный метод для создания записи
    private func postLog(body: [String: Any], completion: @escaping (Result<TrackerStatus, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/tracker/logs") else { completion(.failure(APIError.invalidURL)); return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(APIError.networkError(err))); return }
            switch self.handleHTTPResponse(resp, data: data) {
            case .success:
                self.getTrackerStatus(completion: completion)
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }
    
    // Общий запрос
    private func request<T: Codable>(endpoint: String, method: String, queryParams: [String: String] = [:], body: [String: Any]? = nil, completion: @escaping (Result<T, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        var components = URLComponents(string: baseURL + endpoint)
        if !queryParams.isEmpty { components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components?.url else { completion(.failure(APIError.invalidURL)); return }
        
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        if let body = body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        
        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(APIError.networkError(err))); return }
            switch self.handleHTTPResponse(resp, data: data) {
            case .success:
                guard let data = data else { completion(.failure(APIError.noData)); return }
                do {
                    let decoded = try JSONDecoder().decode(T.self, from: data)
                    completion(.success(decoded))
                } catch { completion(.failure(APIError.decodingError(error))) }
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }

    func getTrackerDailyStats(date: Date, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let _ = formatter.string(from: date)
        
        // Пока заглушка, если на бэке нет такого эндпоинта.
        // В идеале: request(endpoint: "/tracker/stats?date=\(dateStr)", ...)
        // Сейчас вернем пустой результат, так как логика считается на клиенте в TrackerView
        completion(.success(["total_sleep_minutes": 0, "sessions_count": 0]))
    }
}
