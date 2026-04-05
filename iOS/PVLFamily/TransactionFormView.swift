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
    
    // Управление фокусом
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
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Загрузка данных...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // --- БЛОК 1: СУММА И ТИП ---
                        VStack(spacing: 16) {
                            // Поле суммы
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .focused($isAmountFocused)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(type == "income" ? .green : .red)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(20)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(type == "income" ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 2)
                                )
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isAmountFocused = true
                                    }
                                }
                                .onChange(of: amount) { newValue in
                                    let allowed = CharacterSet(charactersIn: "0123456789.,")
                                    if newValue.rangeOfCharacter(from: allowed.inverted) != nil {
                                        amount = newValue.filter { allowed.contains($0.unicodeScalars.first!) }
                                    }
                                }
                            
                            // Переключатель типа
                            Picker("Тип операции", selection: $type) {
                                Text("Расход").tag("expense")
                                Text("Доход").tag("income")
                            }
                            .pickerStyle(.segmented)
                            .tint(type == "income" ? .green : .red)
                            .onChange(of: type) { _, _ in
                                selectedCategoryId = nil
                                selectedSubcategoryId = nil
                            }
                            .overlay(
                                HStack {
                                    Spacer()
                                    Image(systemName: type == "income" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .foregroundColor(type == "income" ? .green : .red)
                                        .font(.title3)
                                        .padding(.trailing, 12)
                                        .allowsHitTesting(false) // Чтобы клики проходили сквозь иконку
                                    Spacer()
                                }
                                .opacity(0.6) // Чуть приглушим, чтобы не отвлекало
                              )
                        }
                        .padding(.horizontal)
                        
                        // --- БЛОК 2: КАТЕГОРИЯ ---
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Категория").font(.headline).foregroundColor(.secondary).padding(.horizontal, 4)
                            
                            // Основная категория
                            Menu {
                                ForEach(categories.filter { $0.parent_id == nil && $0.type == type }) { cat in
                                    Button(action: {
                                        selectedCategoryId = cat.id
                                        selectedSubcategoryId = nil
                                    }) {
                                        HStack {
                                            Text(cat.name)
                                            Spacer()
                                            if selectedCategoryId == cat.id && selectedSubcategoryId == nil {
                                                Image(systemName: "checkmark").foregroundColor(.blue)
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill").foregroundColor(.blue)
                                    Text(selectedCategoryId != nil ? (categories.first(where: { $0.id == selectedCategoryId })?.name ?? "Выберите категорию") : "Выберите категорию")
                                        .foregroundColor(selectedCategoryId != nil ? .primary : .secondary)
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                            }
                            
                            // Подкатегория (если есть)
                            if let catId = selectedCategoryId, !subCategories.isEmpty {
                                Menu {
                                    ForEach(subCategories) { sub in
                                        Button(action: {
                                            selectedSubcategoryId = sub.id
                                        }) {
                                            HStack {
                                                Text("↳ " + sub.name)
                                                Spacer()
                                                if selectedSubcategoryId == sub.id {
                                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "tag.fill").foregroundColor(.orange)
                                        Text(selectedSubcategoryId != nil ? (subCategories.first(where: { $0.id == selectedSubcategoryId })?.name ?? "Подкатегория") : "Все подкатегории")
                                            .foregroundColor(selectedSubcategoryId != nil ? .primary : .secondary)
                                        Spacer()
                                        Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(16)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                }
                            } else if selectedCategoryId != nil {
                                Text("Нет подкатегорий").font(.caption).foregroundColor(.secondary).padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal)
                        
                        // --- БЛОК 3: ДАТА И ЗАМЕТКА ---
                                                VStack(alignment: .leading, spacing: 12) {
                                                    Text("Детали").font(.headline).foregroundColor(.secondary).padding(.horizontal, 4)
                                                    
                                                    // Дата (ТОЛЬКО ДАТА, без времени)
                                                    DatePicker("Дата операции", selection: $date, displayedComponents: .date)
                                                        .datePickerStyle(.compact)
                                                        .padding()
                                                        .background(Color(.systemBackground))
                                                        .cornerRadius(16)
                                                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                                    
                                                    // Заметка
                                                    TextField("Заметка (необязательно)", text: $note)
                                                        .padding()
                                                        .background(Color(.systemBackground))
                                                        .cornerRadius(16)
                                                        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                                }
                                                .padding(.horizontal)
                                                                        
                        // --- КНОПКИ ДЕЙСТВИЙ ---
                        VStack(spacing: 12) {
                            // Сохранить
                            Button(action: submit) {
                                HStack {
                                    Image(systemName: transactionToEdit == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                                    Text(transactionToEdit == nil ? "Создать операцию" : "Сохранить изменения")
                                        .fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(amount.isEmpty || finalCategoryId == nil ? Color.gray : (type == "income" ? Color.green : Color.red))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(color: (type == "income" ? Color.green : Color.red).opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                            .disabled(amount.isEmpty || finalCategoryId == nil)
                            .animation(.easeInOut, value: amount.isEmpty)
                            
                            // Удалить (только при редактировании)
                            if transactionToEdit != nil {
                                Button(role: .destructive, action: {
                                    if let t = transactionToEdit { onDelete(t.id); isPresented = false }
                                }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text("Удалить транзакцию")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(16)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        Spacer(minLength: 40)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground)) // Фон как в настройках
            .navigationTitle(transactionToEdit == nil ? "Новая операция" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                }
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

//#if DEBUG
//struct TransactionFormView_Previews: PreviewProvider {
//    static var previews: some View {
//        Text("Preview requires Mock Data")
//    }
//}
//#endif
