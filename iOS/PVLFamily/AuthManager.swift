import Foundation
import Combine
import LocalAuthentication
import Security

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
    @Published var loginUsers: [[String: Any]] = []
    @Published var requiresPasswordReset: Bool = false
    /// Роль после логина / ответа GET /auth/me (управление пользователями — только при true).
    @Published var isAdmin: Bool = false

    private let userIsAdminKey = "userIsAdmin"

    @Published var selectedServer: ServerMode {
         didSet {
             // Сохраняем выбор сразу при изменении
             let rawValue = selectedServer == .cloud ? "cloud" : "local"
             UserDefaults.standard.set(rawValue, forKey: "savedServerMode")
             updateBaseURL()
         }
     }

    var baseURL: String = "http://127.0.0.1:8000"
    private var pendingResetToken: String?
    private let defaults = UserDefaults.standard
    private let lastLoginNameKey = "lastLoginName"
    private let biometricEnabledKey = "biometricEnabled"
    @Published var biometricEnabled: Bool = false
    
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
        biometricEnabled = defaults.bool(forKey: biometricEnabledKey)
        loadStoredUser()
        loadPublicUsers()
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
        if isLoggedIn {
            syncSessionProfile()
        } else {
            loadPublicUsers()
        }
    }

    func setBiometricEnabled(_ enabled: Bool) {
        biometricEnabled = enabled
        defaults.set(enabled, forKey: biometricEnabledKey)
    }

    func lastLoginName() -> String? {
        defaults.string(forKey: lastLoginNameKey)
    }

    func canUseBiometrics() -> Bool {
        var error: NSError?
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
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
        //print("🔑 TOKEN VALUE: \(savedToken)")
        print("🔑 [AUTH] Name: \(savedName ?? "Нет")")
        print("🔑 [AUTH] ID: \(hasIdKey ? String(savedId) : "Не задан")")
        
        if let token = savedToken, let name = savedName {
            if hasIdKey && savedId != 0 {
                self.token = token
                self.userName = name
                self.userId = savedId
                self.isLoggedIn = true
                print("✅ [AUTH] Сессия восстановлена успешно: \(name)")
                if defaults.object(forKey: userIsAdminKey) != nil {
                    isAdmin = defaults.bool(forKey: userIsAdminKey)
                }
                syncSessionProfile()
            } else {
                print("⚠️ [AUTH] Сессия неполная (нет ID или ID=0). Выполняем выход.")
                logout() // Здесь и происходит сброс, если ID потерян
            }
        } else {
            print("ℹ️ [AUTH] Данные не найдены. Пользователь гость.")
        }
    }

    /// Синхронизирует признак админа с сервером после восстановления токена, затем подгружает список для UI.
    func syncSessionProfile() {
        guard let token = token else { return }
        guard let url = URL(string: "\(baseURL)/auth/me") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if error != nil {
                    self.loadUsers()
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.loadUsers()
                    return
                }
                if let ia = json["is_admin"] as? Bool {
                    self.isAdmin = ia
                    self.defaults.set(ia, forKey: self.userIsAdminKey)
                }
                self.loadUsers()
            }
        }.resume()
    }

    func loadUsers() {
        guard let token = token else {
            self.users = []
            return
        }
        let path = isAdmin ? "/auth/users" : "/auth/users/members"
        guard let url = URL(string: "\(baseURL)\(path)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = APIError.networkError(error).errorDescription
                    return
                }
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                        self.users = json
                    }
                case .failure(let apiError):
                    if !self.isAdmin, let http = response as? HTTPURLResponse, http.statusCode == 403 {
                        self.users = []
                    } else {
                        self.errorMessage = apiError.errorDescription
                    }
                }
            }
        }.resume()
    }

    func loadPublicUsers() {
        guard let url = URL(string: "\(baseURL)/auth/users/public") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = APIError.networkError(error).errorDescription
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    self.errorMessage = "Не удалось загрузить список пользователей"
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.errorMessage = "Некорректный список пользователей"
                    return
                }
                self.loginUsers = json
            }
        }.resume()
    }
    
    func login(name: String, password: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Введите имя"; return }
        guard !password.isEmpty else { errorMessage = "Введите пароль"; return }
        guard let url = URL(string: "\(baseURL)/auth/login") else { errorMessage = APIError.invalidURL.errorDescription; return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        do { request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "password": password]) }
        catch { errorMessage = "Ошибка формирования запроса"; return }
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { self.errorMessage = APIError.networkError(error).errorDescription; return }
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = APIError.serverError.errorDescription
                    return
                }
                // 401 на /auth/login — неверные учётные данные, не «сессия истекла» (см. handleHTTPResponse)
                if httpResponse.statusCode == 401 {
                    let msg = Self.apiErrorMessage(from: data)
                    if msg == "Неизвестная ошибка" || msg.isEmpty {
                        self.errorMessage = "Неверное имя или пароль"
                    } else {
                        self.errorMessage = msg
                    }
                    return
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    self.errorMessage = APIError.httpError(
                        statusCode: httpResponse.statusCode,
                        message: Self.apiErrorMessage(from: data)
                    ).errorDescription
                    return
                }
                guard let data = data else { self.errorMessage = APIError.noData.errorDescription; return }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let accessToken = json["access_token"] as? String,
                          let nameResp = json["name"] as? String,
                          let userId = json["user_id"] as? Int else {
                        throw APIError.decodingError(NSError(domain: "JSON", code: -1, userInfo: [:]))
                    }
                    let mustReset = json["force_password_reset"] as? Bool ?? false
                    let isAdminResp = json["is_admin"] as? Bool ?? false
                    if mustReset {
                        self.pendingResetToken = accessToken
                        self.requiresPasswordReset = true
                        self.isLoggedIn = false
                        self.errorMessage = "Нужно сменить временный пароль"
                        print("⚠️ Требуется принудительная смена пароля для \(nameResp)")
                    } else {
                        self.token = accessToken
                        self.userName = nameResp
                        self.userId = userId
                        self.isAdmin = isAdminResp
                        self.isLoggedIn = true
                        self.requiresPasswordReset = false
                        self.pendingResetToken = nil
                        self.errorMessage = nil
                        UserDefaults.standard.set(accessToken, forKey: "userToken")
                        UserDefaults.standard.set(nameResp, forKey: "userName")
                        UserDefaults.standard.set(userId, forKey: "userId")
                        self.defaults.set(isAdminResp, forKey: self.userIsAdminKey)
                        self.defaults.set(nameResp, forKey: self.lastLoginNameKey)
                        if self.biometricEnabled {
                            _ = self.savePasswordToKeychain(password, account: nameResp)
                        }
                        print("✅ Вход: \(nameResp)")
                        self.loadUsers()
                    }
                } catch { self.errorMessage = APIError.decodingError(error).errorDescription }
            }
        }.resume()
    }

    func loginWithBiometrics() {
        guard biometricEnabled else {
            errorMessage = "Face ID выключен в настройках входа"
            return
        }
        guard let name = lastLoginName() else {
            errorMessage = "Нет последнего пользователя для Face ID"
            return
        }
        guard let password = loadPasswordFromKeychain(account: name) else {
            errorMessage = "Нет сохраненного пароля для Face ID"
            return
        }
        let context = LAContext()
        let reason = "Войти как \(name)"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.login(name: name, password: password)
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Face ID не прошел"
                }
            }
        }
    }

    func changePassword(newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard newPassword.count >= 8 else {
            completion(.failure(APIError.httpError(statusCode: 400, message: "Пароль должен быть не короче 8 символов")))
            return
        }
        guard let resetToken = pendingResetToken else {
            completion(.failure(APIError.unauthorized))
            return
        }
        guard let url = URL(string: "\(baseURL)/auth/change-password") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(resetToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["new_password": newPassword])
        session.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(APIError.networkError(error)))
                    return
                }
                switch self.handleHTTPResponse(response, data: data) {
                case .success:
                    self.errorMessage = nil
                    self.pendingResetToken = nil
                    self.requiresPasswordReset = false
                    completion(.success(()))
                case .failure(let apiError):
                    completion(.failure(apiError))
                }
            }
        }.resume()
    }
    
    func logout() {
        isLoggedIn = false
        userName = nil
        userId = nil
        token = nil
        pendingResetToken = nil
        requiresPasswordReset = false
        isAdmin = false
        users = []
        defaults.removeObject(forKey: userIsAdminKey)
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

    func createUserByAdmin(name: String, password: String, isActive: Bool, mustResetPassword: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/auth/users") else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": name,
            "password": password,
            "is_active": isActive,
            "must_reset_password": mustResetPassword
        ])
        session.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(APIError.networkError(error))); return }
            switch self.handleHTTPResponse(response, data: data) {
            case .success: completion(.success(()))
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }

    func updateUserByAdmin(userId: Int, name: String, password: String?, isActive: Bool, mustResetPassword: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/auth/users/\(userId)") else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        var payload: [String: Any] = [
            "name": name,
            "is_active": isActive,
            "must_reset_password": mustResetPassword
        ]
        if let password, !password.isEmpty {
            payload["password"] = password
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        session.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(APIError.networkError(error))); return }
            switch self.handleHTTPResponse(response, data: data) {
            case .success: completion(.success(()))
            case .failure(let apiError): completion(.failure(apiError))
            }
        }.resume()
    }

    private func keychainServiceName() -> String {
        let host = URL(string: baseURL)?.host ?? "pvlfamily"
        return "pvlfamily.auth.\(host)"
    }

    private func savePasswordToKeychain(_ password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let service = keychainServiceName()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadPasswordFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
    }
}

// MARK: - Dashboard Models
struct DashboardSummary: Codable { let balance: Double; let total_income: Double; let total_expense: Double }
struct MonthlyStatDetail: Codable { let category_id: Int?; let category_name: String; let type: String; let amount: Double }
struct MonthlyStats: Codable {
    let year: Int; let month: Int; let total_income: Double; let total_expense: Double; let balance: Double; let details: [MonthlyStatDetail]
}

struct InsightPayload: Codable {
    let report_type: String
    let period: String
    let metrics: [String: Double]
    let trend_flags: [String]
    let anomalies: [[String: Double]]
    /// Дополнительные агрегаты (safe_payload): серии/разбивки/сравнения.
    /// Поля опциональные: backend и клиент совместимы со старым контрактом.
    let series: [InsightSeries]?
    let breakdowns: [InsightBreakdown]?
    let comparisons: [InsightComparison]?
    let notes: String?
}

struct InsightPoint: Codable {
    let t: String
    let v: Double
}

struct InsightSeries: Codable {
    let name: String
    let points: [InsightPoint]
    let unit: String?
}

struct InsightBreakdownItem: Codable {
    let name: String
    let value: Double
    let share: Double?
}

struct InsightBreakdown: Codable {
    let name: String
    let items: [InsightBreakdownItem]
    let unit: String?
}

struct InsightComparison: Codable {
    let name: String
    let a_label: String
    let a_value: Double
    let b_label: String
    let b_value: Double
    let delta: Double?
    let delta_pct: Double?
    let unit: String?
}

struct InsightRequest: Codable {
    let payload: InsightPayload
    let provider: String?
    let question: String?
    let anchor_month: String?
    let window_months: Int?
    let user_id: Int?
}

struct InsightResponse: Codable {
    let provider: String
    let summary_today: String
    let summary_month: String
    let bullets: [String]
    let risk_flags: [String]
    let confidence: Double
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

    /// Агрегаты сна за последние `days` (см. `GET /tracker/stats`).
    func getTrackerStats(days: Int, completion: @escaping (Result<TrackerStats, Error>) -> Void) {
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        let d = min(max(days, 1), 365)
        guard let url = URL(string: "\(baseURL)/tracker/stats?days=\(d)") else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(APIError.networkError(err))); return }
            if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                completion(.failure(APIError.httpError(statusCode: h.statusCode, message: "tracker/stats")))
                return
            }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            do {
                let decoded = try JSONDecoder().decode(TrackerStats.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }

    /// Генерация инсайта через backend `/insights/{kind}`.
    func getInsight(
        kind: String,
        payload: InsightPayload,
        provider: String? = nil,
        question: String? = nil,
        anchorMonth: String? = nil,
        windowMonths: Int? = nil,
        userId: Int? = nil,
        completion: @escaping (Result<InsightResponse, Error>) -> Void
    ) {
        let safeKind = (kind == "tracker") ? "tracker" : "budget"
        let reqBody = InsightRequest(
            payload: payload,
            provider: provider,
            question: question,
            anchor_month: anchorMonth,
            window_months: windowMonths,
            user_id: userId
        )
        guard let token = token else { completion(.failure(APIError.unauthorized)); return }
        guard let url = URL(string: "\(baseURL)/insights/\(safeKind)") else { completion(.failure(APIError.invalidURL)); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        do {
            req.httpBody = try JSONEncoder().encode(reqBody)
        } catch {
            completion(.failure(APIError.decodingError(error)))
            return
        }
        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(APIError.networkError(err))); return }
            if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                completion(.failure(APIError.httpError(statusCode: h.statusCode, message: "insights/\(safeKind)")))
                return
            }
            guard let data else { completion(.failure(APIError.noData)); return }
            do {
                let decoded = try JSONDecoder().decode(InsightResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(APIError.decodingError(error)))
            }
        }.resume()
    }
}
