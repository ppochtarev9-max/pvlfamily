import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var summary: DashboardSummary?
    @State private var stats: MonthlyStats?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Для баланса: выбранная дата (по умолчанию сегодня)
    @State private var balanceDate = Date()
    @State private var showBalanceCalendar = false
    
    // Для детализации: выбранный месяц (по умолчанию текущий)
    @State private var statsMonth = Date()
    
    // Состояния сворачивания секций
    @State private var isIncomeExpanded = false
    @State private var isExpenseExpanded = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Загрузка...")
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 40))
                        Text(error).multilineTextAlignment(.center)
                        Button("Обновить") { loadData() }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            
                            // --- ЗАГОЛОВОК С ДАТОЙ ---
                            HStack(spacing: 8) {
                                Text("Обзор на ")
                                    .font(.system(size: 22, weight: .bold)) // Фиксированный крупный размер
                                    .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                    .lineLimit(1) // Запретить перенос
                                
                                Button(action: { showBalanceCalendar = true }) {
                                    HStack(spacing: 4) {
                                        Text(formatDate(balanceDate))
                                            .fontWeight(.medium)
                                        Image(systemName: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                    .foregroundColor(.primary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .sheet(isPresented: $showBalanceCalendar) {
                                VStack {
                                    DatePicker("", selection: $balanceDate, displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .onChange(of: balanceDate) { _ in
                                            // Закрываем и обновляем сразу при выборе даты
                                            showBalanceCalendar = false
                                            loadBalance()
                                        }
                                    
                                    // Кнопка "Отмена" чтобы просто закрыть без выбора (опционально)
                                    Button("Закрыть") { showBalanceCalendar = false }
                                        .padding()
                                }
                                .presentationDetents([.medium]) // Ограничиваем высоту шторки
                            }
                            
                            // --- КАРТОЧКА БАЛАНСА ---
                            VStack(spacing: 16) {
                                if let s = summary {
                                    Text(formatCurrency(s.balance))
                                        .font(.system(size: 52, weight: .bold))
                                        .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                        .lineLimit(1) // Запретить перенос
                                        .foregroundColor(.blue)
                                    
                                    HStack(spacing: 40) {
                                        VStack(spacing: 4) {
                                            Text("Доходы")
                                                .font(.caption2) // Очень маленький шрифт
                                                .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                                .lineLimit(1) // Запретить перенос
                                                .foregroundColor(.secondary)
                                            Text(formatCurrency(s.total_income))
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                                .lineLimit(1) // Запретить перенос
                                                .foregroundColor(.green)
                                        }
                                        Divider()
                                        VStack(spacing: 4) {
                                            Text("Расходы")
                                                .font(.caption2)
                                                .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                                .lineLimit(1) // Запретить перенос
                                                .foregroundColor(.secondary)
                                            Text(formatCurrency(s.total_expense))
                                                .font(.title3)
                                                .minimumScaleFactor(0.5) // Разрешить сжиматься до 50%
                                                .lineLimit(1) // Запретить перенос
                                                .fontWeight(.semibold)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .shadow(color: Color.blue.opacity(0.15), radius: 12, x: 0, y: 6)
                            
                            // --- КАРТОЧКА ДЕТАЛИЗАЦИИ ПО МЕСЯЦАМ ---
                            VStack(alignment: .leading, spacing: 16) {
                                // Заголовок с переключением
                                HStack {
                                    Button(action: { changeStatsMonth(-1) }) {
                                        Image(systemName: "chevron.left")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(monthYearString(from: statsMonth))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Button(action: { changeStatsMonth(1) }) {
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                if let st = stats {
                                    let incomes = st.details.filter { $0.type == "income" }.sorted { $1.amount > $0.amount } // Сортировка от большего к меньшему
                                    let expenses = st.details.filter { $0.type == "expense" }.sorted { $1.amount > $0.amount }
                                    
                                    // Секция Доходы
                                    if !incomes.isEmpty {
                                        DisclosureGroup(isExpanded: $isIncomeExpanded) {
                                            ForEach(incomes, id: \.category_name) { item in
                                                HStack {
                                                    Text(item.category_name).font(.body)
                                                    Spacer()
                                                    Text(formatCurrency(item.amount)).foregroundColor(.green)
                                                }
                                                .font(.callout)
                                                .padding(.vertical, 2)
                                            }
                                        } label: {
                                            Text("Доходы: " + formatCurrency(st.total_income))
                                                .font(.headline)
                                                .foregroundColor(.green)
                                                .contentShape(Rectangle())
                                        }
                                        .padding(16)
                                        .background(Color.green.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                    
                                    // Секция Расходы
                                    if !expenses.isEmpty {
                                        DisclosureGroup(isExpanded: $isExpenseExpanded) {
                                            ForEach(expenses, id: \.category_name) { item in
                                                HStack {
                                                    Text(item.category_name).font(.body)
                                                    Spacer()
                                                    Text(formatCurrency(item.amount)).foregroundColor(.red)
                                                }
                                                .font(.callout)
                                                .padding(.vertical, 2)
                                            }
                                        } label: {
                                            Text("Расходы: " + formatCurrency(st.total_expense))
                                                .font(.headline)
                                                .foregroundColor(.red)
                                                .contentShape(Rectangle())
                                        }
                                        .padding(16)
                                        .background(Color.red.opacity(0.05))
                                        .cornerRadius(12)
                                    }
                                    
                                    if incomes.isEmpty && expenses.isEmpty {
                                        Text("Нет операций за этот месяц")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding()
                                    }
                                    
                                    // Итого за месяц
                                    VStack(spacing: 4) {
                                        Divider()
                                        HStack {
                                            Text("Итого за месяц:")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text(formatCurrency(st.balance))
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(st.balance >= 0 ? .blue : .orange)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(20)
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("") // Скрываем стандартный заголовок
            .onAppear(perform: loadData) // <--- ВОТ ЭТОГО НЕ ХВАТАЛО!
        }
    }
    
    // --- Helpers ---
    
    func monthYearString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date).capitalized
    }
    
    func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date)
    }
    
    func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: abs(value))) ?? "0") ₽"
    }
    
    func changeStatsMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: statsMonth) {
            statsMonth = newDate
            loadStats()
        }
    }
    
    func loadData() {
        print("🔄 [DEBUG] loadData вызван")
        isLoading = true
        errorMessage = nil
        loadBalance()
        loadStats()
    }
    
    func loadBalance() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: balanceDate)
        
        print("📡 [DEBUG] Запрос баланса на дату: \(dateStr)")
        
        authManager.getDashboardSummary(asOfDate: dateStr, userId: nil) { result in
            DispatchQueue.main.async {
                print("📥 [DEBUG] Ответ баланса получен")
                switch result {
                case .success(let data):
                    print("✅ [DEBUG] Баланс: \(data.balance)")
                    self.summary = data
                case .failure(let error):
                    print("❌ [DEBUG] Ошибка баланса: \(error.localizedDescription)")
                    self.errorMessage = "Ошибка загрузки баланса: \(error.localizedDescription)"
                }
                
                // Логика снятия флага загрузки
                if self.stats != nil || self.errorMessage != nil {
                    self.isLoading = false
                    print("⏹ [DEBUG] Загрузка завершена (статистика уже есть или ошибка)")
                } else {
                    print("⏳ [DEBUG] Ждем статистику...")
                }
            }
        }
    }
    
    func loadStats() {
        let comps = Calendar.current.dateComponents([.year, .month], from: statsMonth)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        
        print("📡 [DEBUG] Запрос статистики за: \(y)-\(m)")
        
        authManager.getMonthlyStats(year: y, month: m, userId: nil) { result in
            DispatchQueue.main.async {
                print("📥 [DEBUG] Ответ статистики получен")
                switch result {
                case .success(let data):
                    print("✅ [DEBUG] Статистика: доходов=\(data.total_income), расходов=\(data.total_expense)")
                    self.stats = data
                case .failure(let error):
                    print("❌ [DEBUG] Ошибка статистики: \(error.localizedDescription)")
                    self.errorMessage = "Ошибка загрузки статистики: \(error.localizedDescription)"
                }
                
                // Логика снятия флага загрузки
                if self.summary != nil || self.errorMessage != nil {
                    self.isLoading = false
                    print("⏹ [DEBUG] Загрузка завершена (баланс уже есть или ошибка)")
                } else {
                    print("⏳ [DEBUG] Ждем баланс...")
                }
            }
        }
    }
}
