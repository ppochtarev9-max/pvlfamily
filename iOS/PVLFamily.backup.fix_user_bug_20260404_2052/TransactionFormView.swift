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
    @State private var selectedSubcategoryId: Int? = nil
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var isLoading = false
    
    // Добавляем управление фокусом
    @FocusState private var isAmountFocused: Bool
    
    init(isPresented: Binding<Bool>, categories: [BudgetView.Category], transactionToEdit: BudgetView.Transaction?, onSave: @escaping (Int?, Double, String, Int, String, Date) -> Void, onDelete: @escaping (Int) -> Void) {
        self._isPresented = isPresented
        self.categories = categories
        self.transactionToEdit = transactionToEdit
        self.onSave = onSave
        self.onDelete = onDelete
        
        if let t = transactionToEdit {
            _amount = State(initialValue: String(format: "%.2f", abs(t.amount)))
            _type = State(initialValue: t.transaction_type)
            _note = State(initialValue: t.description ?? "")
            _date = State(initialValue: Date())
            
            if let cat = categories.first(where: { $0.id == t.category_id }) {
                if let pid = cat.parent_id {
                    _selectedCategoryId = State(initialValue: pid)
                    _selectedSubcategoryId = State(initialValue: t.category_id)
                } else {
                    _selectedCategoryId = State(initialValue: t.category_id)
                    _selectedSubcategoryId = State(initialValue: nil)
                }
            } else {
                _selectedCategoryId = State(initialValue: t.category_id)
            }
        }
    }
    
    var subCategories: [BudgetView.Category] {
        guard let catId = selectedCategoryId else { return [] }
        return categories.filter { $0.parent_id == catId && $0.type == type }
    }
    
    var finalCategoryId: Int? {
        selectedSubcategoryId ?? selectedCategoryId
    }
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Загрузка...")
                } else {
                    // Секция 1: Сумма
                    Section("Сумма") {
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused($isAmountFocused) // Привязываем фокус
                            .onAppear {
                                // Небольшая задержка, чтобы UI успел отрисоваться
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isAmountFocused = true
                                }
                            }
                            .onChange(of: amount) { newValue in
                                // Фильтр: только цифры, точка, запятая
                                let allowed = CharacterSet(charactersIn: "0123456789.,")
                                if newValue.rangeOfCharacter(from: allowed.inverted) != nil {
                                    amount = newValue.filter { allowed.contains($0.unicodeScalars.first!) }
                                }
                            }
                            .font(.system(size: 24, weight: .semibold)) // Крупный шрифт для удобства
                            .foregroundColor(type == "income" ? .green : .red) // Цвет зависит от типа
                    }
                    
                    // Секция 2: Тип операции
                    Section("Тип операции") {
                        Picker("Выберите тип", selection: $type) {
                            Text("Расход").tag("expense")
                            Text("Доход").tag("income")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: type) { _, _ in
                            selectedCategoryId = nil
                            selectedSubcategoryId = nil
                            // Меняем цвет суммы при смене типа
                            if let val = Double(amount), val != 0 {
                                // Можно добавить анимацию или просто оставить цвет
                            }
                        }
                    }
                    
                    // Секция 3: Дата
                    Section("Дата") {
                        DatePicker("Дата операции", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    }
                    
                    // Секция 4: Категория
                    Section("Категория") {
                        Picker("Категория", selection: $selectedCategoryId) {
                            Text("Выберите...").tag(nil as Int?)
                            ForEach(categories.filter { $0.parent_id == nil && $0.type == type }) { cat in
                                Text(cat.name).tag(cat.id as Int?)
                            }
                        }
                        
                        if !subCategories.isEmpty {
                            Picker("Подкатегория", selection: $selectedSubcategoryId) {
                                Text("Не выбрано").tag(nil as Int?)
                                ForEach(subCategories) { sub in
                                    Text(sub.name).tag(sub.id as Int?)
                                }
                            }
                        }
                    }
                    
                    // Секция 5: Заметка
                    Section("Заметка") {
                        TextField("Описание", text: $note)
                    }
                    
                    // Секция 6: Удаление (если редактирование)
                    if transactionToEdit != nil {
                        Section {
                            Button(role: .destructive, action: {
                                if let t = transactionToEdit { onDelete(t.id); isPresented = false }
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Удалить транзакцию")
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // Кнопка сохранения (всегда внизу)
                    Section {
                        Button(action: submit) {
                            Text(transactionToEdit == nil ? "Создать" : "Сохранить")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.bold)
                        }
                        .disabled(amount.isEmpty || finalCategoryId == nil)
                    }
                }
            }
            .navigationTitle(transactionToEdit == nil ? "Новая операция" : "Редактирование")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false } }
            }
            .task {
                if let t = transactionToEdit {
                    await loadDetails(id: t.id)
                }
            }
        }
    }
    
    func loadDetails(id: Int) async {
        isLoading = true
        guard let token = authManager.token else { return }
        let url = "\(authManager.baseURL)/budget/transactions/\(id)"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let tx = try JSONDecoder().decode(BudgetView.Transaction.self, from: data)
            
            DispatchQueue.main.async {
                self.amount = String(format: "%.2f", abs(tx.amount))
                self.type = tx.transaction_type
                self.note = tx.description ?? ""
                
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: tx.date) {
                    self.date = d
                } else {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                    df.locale = Locale(identifier: "en_US_POSIX")
                    if let d = df.date(from: tx.date) { self.date = d }
                }
                
                if let cat = categories.first(where: { $0.id == tx.category_id }) {
                    if let pid = cat.parent_id {
                        self.selectedCategoryId = pid
                        self.selectedSubcategoryId = tx.category_id
                    } else {
                        self.selectedCategoryId = tx.category_id
                        self.selectedSubcategoryId = nil
                    }
                } else {
                    self.selectedCategoryId = tx.category_id
                }
                
                self.isLoading = false
                // Фокус на сумму после загрузки данных
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isAmountFocused = true
                }
            }
        } catch {
            print("Ошибка загрузки: \(error)")
            DispatchQueue.main.async { isLoading = false }
        }
    }
    
    func submit() {
        guard let val = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
        let finalAmt = type == "expense" ? -abs(val) : abs(val)
        guard let catId = finalCategoryId else { return }
        onSave(transactionToEdit?.id, finalAmt, type, catId, note, date)
    }
}

#if DEBUG
struct TransactionFormView_Previews: PreviewProvider {
    static var previews: some View {
        // Тут нужен мок данных, но можно просто оставить пустым, если сложно
        Text("Preview requires Mock Data")
    }
}
#endif
