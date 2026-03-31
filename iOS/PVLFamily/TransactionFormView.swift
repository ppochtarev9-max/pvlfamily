import SwiftUI

struct TransactionFormView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    let categories: [BudgetView.Category]
    let transactionToEdit: BudgetView.Transaction?
    let onSave: (Int?, Double, String, Int, String, Date) -> Void
    let onDelete: (Int) -> Void
    
    @State private var amount: String = ""
    @State private var type: String = "expense"
    @State private var selectedCategoryId: Int? = nil
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var showingCategoryPicker = false
    @State private var isLoading = false
    
    init(isPresented: Binding<Bool>, categories: [BudgetView.Category], transactionToEdit: BudgetView.Transaction?, onSave: @escaping (Int?, Double, String, Int, String, Date) -> Void, onDelete: @escaping (Int) -> Void) {
        self._isPresented = isPresented
        self.categories = categories
        self.transactionToEdit = transactionToEdit
        self.onSave = onSave
        self.onDelete = onDelete
        
        if let t = transactionToEdit {
            _amount = State(initialValue: String(format: "%.2f", abs(t.amount)))
            _type = State(initialValue: t.transaction_type)
            _selectedCategoryId = State(initialValue: t.category_id)
            _note = State(initialValue: t.description ?? "")
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: t.date) { _date = State(initialValue: d) }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Загрузка данных...")
                } else {
                    Section(header: Text("Сумма")) {
                        TextField("0.00", text: $amount).keyboardType(.decimalPad)
                        Picker("Тип", selection: $type) {
                            Text("Расход").tag("expense")
                            Text("Доход").tag("income")
                        }.pickerStyle(.segmented)
                        .onChange(of: type) { _, _ in
                            selectedCategoryId = nil // Сброс категории при смене типа
                        }
                    }
                    
                    Section(header: Text("Дата")) {
                        DatePicker("Дата операции", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    }
                    
                    Section(header: Text("Категория")) {
                        Button(action: { showingCategoryPicker = true }) {
                            HStack {
                                Text(getCategoryName(id: selectedCategoryId))
                                    .foregroundColor(selectedCategoryId == nil ? .orange : .primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Section(header: Text("Заметка")) {
                        TextField("Описание", text: $note)
                    }
                    
                    if transactionToEdit != nil {
                        Section {
                            Button(role: .destructive, action: {
                                if let t = transactionToEdit { onDelete(t.id); isPresented = false }
                            }) {
                                Text("Удалить транзакцию")
                            }
                        }
                    }
                    
                    Button(action: submit) {
                        Text(transactionToEdit == nil ? "Создать" : "Сохранить")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(amount.isEmpty || selectedCategoryId == nil)
                }
            }
            .navigationTitle(transactionToEdit == nil ? "Новая операция" : "Редактирование")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false } }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                // Передаем текущий выбранный тип для фильтрации
                CategorySelectionView(categories: categories, selectedId: $selectedCategoryId, filterType: type, onSelect: { showingCategoryPicker = false })
            }
            .task {
                if let t = transactionToEdit {
                    await loadTransactionDetails(id: t.id)
                }
            }
        }
    }
    
    func loadTransactionDetails(id: Int) async {
        isLoading = true
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/transactions/\(id)")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let tx = try JSONDecoder().decode(BudgetView.Transaction.self, from: data)
            
            DispatchQueue.main.async {
                self.amount = String(format: "%.2f", abs(tx.amount))
                self.type = tx.transaction_type
                self.selectedCategoryId = tx.category_id
                self.note = tx.description ?? ""
                let iso = ISO8601DateFormatter()
                if let d = iso.date(from: tx.date) { self.date = d }
                self.isLoading = false
            }
        } catch {
            print("Ошибка загрузки: \(error)")
            DispatchQueue.main.async { isLoading = false }
        }
    }
    
    func getCategoryName(id: Int?) -> String {
        guard let id = id else { return "Выберите категорию" }
        if let cat = categories.first(where: { $0.id == id }) {
            if let pid = cat.parent_id, let parent = categories.first(where: { $0.id == pid }) {
                return "\(parent.name) / \(cat.name)"
            }
            return cat.name
        }
        return "Категория не найдена"
    }
    
    func submit() {
        guard let val = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
        let finalAmt = type == "expense" ? -abs(val) : abs(val)
        guard let catId = selectedCategoryId else { return }
        onSave(transactionToEdit?.id, finalAmt, type, catId, note, date)
    }
}
