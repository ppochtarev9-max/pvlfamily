import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var summary: DashboardSummary?
    @State private var stats: MonthlyStats?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Фильтры
    @State private var selectedDate = Date()
    @State private var showAllUsers = false // false = только я, true = все
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка...")
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Ошибка: " + error).multilineTextAlignment(.center)
                        Button("Обновить") { loadData() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            
                            // Панель фильтров
                            VStack(spacing: 10) {
                                DatePicker("Дата среза:", selection: $selectedDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                
                                Toggle(isOn: $showAllUsers) {
                                    Text(showAllUsers ? "Пользователь: Все" : "Пользователь: Я")
                                }
                                .toggleStyle(.switch)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                            
                            // Карточка баланса
                            if let s = summary {
                                VStack(spacing: 15) {
                                    Text("Баланс на \(formatDate(selectedDate))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text(String(format: "%.2f ₽", s.balance))
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(s.balance >= 0 ? .green : .red)
                                    
                                    HStack {
                                        VStack {
                                            Text("Доход").font(.caption)
                                            Text(String(format: "+%.2f", s.total_income)).foregroundColor(.green)
                                        }
                                        Divider()
                                        VStack {
                                            Text("Расход").font(.caption)
                                            Text(String(format: "%.2f", s.total_expense)).foregroundColor(.red)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(10)
                                .shadow(radius: 2)
                                
                                // Детализация
                                if let st = stats, !st.details.isEmpty {
                                    Text("Детализация за месяц:").font(.subheadline).bold().padding(.top)
                                    ForEach(st.details, id: \.category_name) { item in
                                        HStack {
                                            Text(item.category_name)
                                            Spacer()
                                            Text(String(format: "%.2f", item.amount))
                                                .foregroundColor(item.type == "income" ? .green : .red)
                                        }
                                        .font(.caption)
                                        .padding(.vertical, 2)
                                    }
                                }
                            } else if errorMessage == nil {
                                Text("Нет данных для отображения").frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Обзор")
            .onAppear(perform: loadData)
            .onChange(of: selectedDate) { _ in loadData() }
            .onChange(of: showAllUsers) { _ in loadData() }
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: date)
    }
    
    func loadData() {
        isLoading = true
        errorMessage = nil
        
        // Формируем дату в строку YYYY-MM-DD HH:MM:SS
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone.current
        let dateStr = df.string(from: selectedDate)
        
        // Определяем userId: nil значит "все", иначе ID текущего
        let userId: Int? = showAllUsers ? nil : getCurrentUserId()
        
        authManager.getDashboardSummary(asOfDate: dateStr, userId: userId) { res in
            DispatchQueue.main.async {
                if case .success(let d) = res { self.summary = d }
                else { self.errorMessage = "Ошибка баланса" }
                isLoading = false
            }
        }
        
        authManager.getMonthlyStats(userId: userId) { res in
            DispatchQueue.main.async {
                if case .success(let d) = res { self.stats = d }
                else if self.errorMessage == nil { self.errorMessage = "Ошибка статистики" }
            }
        }
    }
    
    // Вспомогательная функция для получения ID из токена (упрощенно)
    func getCurrentUserId() -> Int? {
        // В реальном проекте лучше декодировать JWT или хранить ID в AuthManager
        // Пока вернем 1 как заглушку, если нужно, доработаем AuthManager
        return 1 
    }
}
