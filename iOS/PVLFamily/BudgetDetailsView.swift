import SwiftUI

struct BudgetDetailsView: View {
    @EnvironmentObject var authManager: AuthManager
    
    // Связанные переменные фильтров от родителя
    @Binding var selectedUserId: Int?
    @Binding var selectedDateFilter: BudgetView.DateFilter
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    @Binding var selectedGroupId: Int?      // ИЗМЕНЕНО: было categoryId
    @Binding var selectedSubcategoryId: Int?

    let initialMonth: Date?
    
    @State private var stats: MonthlyStats?
    @State private var isLoading = false
    @State private var statsMonth: Date
    @State private var isIncomeExpanded = false
    @State private var isExpenseExpanded = false

    init(
        selectedUserId: Binding<Int?>,
        selectedDateFilter: Binding<BudgetView.DateFilter>,
        customStartDate: Binding<Date>,
        customEndDate: Binding<Date>,
        selectedGroupId: Binding<Int?>,
        selectedSubcategoryId: Binding<Int?>,
        initialMonth: Date? = nil
    ) {
        _selectedUserId = selectedUserId
        _selectedDateFilter = selectedDateFilter
        _customStartDate = customStartDate
        _customEndDate = customEndDate
        _selectedGroupId = selectedGroupId
        _selectedSubcategoryId = selectedSubcategoryId
        self.initialMonth = initialMonth
        let cal = Calendar.current
        let base = initialMonth ?? Date()
        let comps = cal.dateComponents([.year, .month], from: base)
        _statsMonth = State(initialValue: cal.date(from: comps) ?? base)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Заголовок с переключением месяцев
                HStack {
                    Button(action: { changeStatsMonth(-1) }) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FamilyAppStyle.accent)
                    }
                    Spacer()
                    Text(monthYearString(from: statsMonth))
                        .font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Button(action: { changeStatsMonth(1) }) {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(FamilyAppStyle.accent)
                    }
                }
                .padding(.horizontal)
                
                if let st = stats {
                    let incomes = st.details.filter { $0.type == "income" }.sorted { $1.amount > $0.amount }
                    let expenses = st.details.filter { $0.type == "expense" }.sorted { $1.amount > $0.amount }
                    
                    if !incomes.isEmpty {
                        DisclosureGroup(isExpanded: $isIncomeExpanded) {
                            ForEach(incomes, id: \.category_name) { item in
                                HStack {
                                    Text(item.category_name).font(.body)
                                    Spacer()
                                    Text(formatCurrency(item.amount)).foregroundColor(.green)
                                }
                                .font(.callout).padding(.vertical, 2)
                            }
                        } label: {
                            Text("Доходы: " + formatCurrency(st.total_income))
                                .font(.headline).foregroundColor(.green)
                                .contentShape(Rectangle())
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.green.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.green.opacity(0.28), lineWidth: 1)
                        )
                    }
                    
                    if !expenses.isEmpty {
                        DisclosureGroup(isExpanded: $isExpenseExpanded) {
                            ForEach(expenses, id: \.category_name) { item in
                                HStack {
                                    Text(item.category_name).font(.body)
                                    Spacer()
                                    Text(formatCurrency(item.amount)).foregroundColor(.red)
                                }
                                .font(.callout).padding(.vertical, 2)
                            }
                        } label: {
                            Text("Расходы: " + formatCurrency(st.total_expense))
                                .font(.headline).foregroundColor(.red)
                                .contentShape(Rectangle())
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
                        )
                    }
                    
                    if incomes.isEmpty && expenses.isEmpty {
                        Text("Нет операций за этот месяц")
                            .font(.callout).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center).padding()
                    }
                    
                    VStack(spacing: 4) {
                        Divider()
                        HStack {
                            Text("Итого за месяц:").font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Text(formatCurrency(st.balance))
                                .font(.subheadline).fontWeight(.bold)
                                .foregroundColor(st.balance >= 0 ? FamilyAppStyle.accent : .orange)
                        }
                    }
                    .padding(16)
                    .background(FamilyAppStyle.listCardFill)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
                    )
                    .padding(.top, 4)
                } else if isLoading {
                    ProgressView()
                } else {
                    Text("Нет данных").foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Детализация")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadStats)
    }
    
    func monthYearString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        f.locale = Locale(identifier: "ru_RU")
        return f.string(from: date).capitalized
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
    
    func loadStats() {
        isLoading = true
        let comps = Calendar.current.dateComponents([.year, .month], from: statsMonth)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        
        authManager.getMonthlyStats(year: y, month: m, userId: selectedUserId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data): self.stats = data
                case .failure(let error): print("Ошибка статистики: \(error)")
                }
                self.isLoading = false
            }
        }
    }
}
