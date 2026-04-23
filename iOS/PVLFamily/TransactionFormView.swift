import SwiftUI

// ⚠️ ВСТАВЬ СЮДА ID, КОТОРЫЙ ВЫДАСТ СКРИПТ ПОСЛЕ УСПЕШНОГО ЗАПУСКА
let DEFAULT_SUBCATEGORY_ID = 110

struct TransactionFormView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    let categoryGroups: [BudgetView.CategoryGroup]
    let transactionToEdit: BudgetView.Transaction?
    let onSave: (Int?, Double, String, Int?, String, Date) -> Void
    let onDelete: (Int) -> Void
    
    @State private var amount: String = ""
    @State private var type: String = "expense"
    @State private var selectedGroupId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil
    @State private var note: String = ""
    @State private var date: Date = Date()
    
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var showingCategorySheet = false
    
    @FocusState private var isAmountFocused: Bool
    
    init(isPresented: Binding<Bool>, categoryGroups: [BudgetView.CategoryGroup], transactionToEdit: BudgetView.Transaction?, onSave: @escaping (Int?, Double, String, Int?, String, Date) -> Void, onDelete: @escaping (Int) -> Void) {
        self._isPresented = isPresented
        self.categoryGroups = categoryGroups
        self.transactionToEdit = transactionToEdit
        self.onSave = onSave
        self.onDelete = onDelete
        
        if let t = transactionToEdit {
            _amount = State(initialValue: String(format: "%.2f", abs(t.amount)))
            _type = State(initialValue: t.transaction_type)
            _note = State(initialValue: t.description ?? "")
            _date = State(initialValue: Date())
            
            if let gid = findGroupId(forSubcategoryId: t.category_id, in: categoryGroups) {
                _selectedGroupId = State(initialValue: gid)
                _selectedSubcategoryId = State(initialValue: t.category_id)
            }
        }
    }
    
    func findGroupId(forSubcategoryId subId: Int, in groups: [BudgetView.CategoryGroup]) -> Int? {
        for g in groups {
            if g.subcategories.contains(where: { $0.id == subId }) {
                return g.id
            }
        }
        return nil
    }
    
    var availableSubcategories: [BudgetView.SubCategory] {
        guard let gid = selectedGroupId,
              let group = categoryGroups.first(where: { $0.id == gid }) else { return [] }
        return group.subcategories.filter { !$0.is_hidden }
    }
    
    // Если ничего не выбрано, возвращаем nil (логика заглушки будет в submit)
    var finalCategoryId: Int? {
        return selectedSubcategoryId
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Загрузка...").frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // СУММА И ТИП
                        VStack(spacing: 16) {
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(type == "income" ? .green : .red)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(20)
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(type == "income" ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 2))
                                .disabled(isSaving)
                                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isAmountFocused = true } }
                            
                            Picker("Тип операции", selection: $type) {
                                Text("Расход").tag("expense")
                                Text("Доход").tag("income")
                            }
                            .pickerStyle(.segmented)
                            .tint(type == "income" ? .green : .red)
                            .disabled(isSaving)
                            .onChange(of: type) { _, _ in
                                selectedGroupId = nil
                                selectedSubcategoryId = nil
                            }
                        }
                        .padding(.horizontal)
                        
                        // КАТЕГОРИЯ
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Категория").font(.headline).foregroundColor(.secondary).padding(.horizontal, 4)
                            
                            Button(action: { showingCategorySheet = true }) {
                                HStack {
                                    Image(systemName: "tag.fill").foregroundColor(.blue)
                                    if let gid = selectedGroupId, let group = categoryGroups.first(where: { $0.id == gid }) {
                                        if let sid = selectedSubcategoryId, let sub = group.subcategories.first(where: { $0.id == sid }) {
                                            Text("\(group.name) / \(sub.name)").foregroundColor(.primary)
                                        } else {
                                            Text("\(group.name) (выберите подкатегорию)").foregroundColor(.orange)
                                        }
                                    } else {
                                        Text("Выберите категорию").foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                            }
                            .disabled(isSaving)
                        }
                        .padding(.horizontal)
                        
                        // ДАТА И ЗАМЕТКА
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Детали").font(.headline).foregroundColor(.secondary).padding(.horizontal, 4)
                            DatePicker("Дата операции", selection: $date, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .disabled(isSaving)
                            TextField("Заметка", text: $note)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .disabled(isSaving)
                        }
                        .padding(.horizontal)
                                                                        
                        // КНОПКИ
                        VStack(spacing: 12) {
                            Button(action: submit) {
                                HStack {
                                    if isSaving { ProgressView().scaleEffect(0.8) }
                                    else { Image(systemName: transactionToEdit == nil ? "plus.circle.fill" : "checkmark.circle.fill") }
                                    Text(isSaving ? "Сохранение..." : (transactionToEdit == nil ? "Создать" : "Сохранить")).fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background((type == "income" ? Color.green : Color.red))
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                            .disabled(isSaving) // Убрали проверку finalCategoryId == nil, так как теперь есть заглушка
                            
                            if transactionToEdit != nil {
                                Button(role: .destructive, action: { if let t = transactionToEdit { onDelete(t.id) } }) {
                                    HStack { Image(systemName: "trash.fill"); Text("Удалить") }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(16)
                                }
                                .disabled(isSaving)
                            }
                        }
                        .padding(.horizontal)
                        Spacer(minLength: 40)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(transactionToEdit == nil ? "Новая операция" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false }.disabled(isSaving) }
            }
            .alert("Ошибка", isPresented: $showErrorAlert) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showingCategorySheet) {
                CategorySelectionView(
                    groups: categoryGroups,
                    selectedGroupId: $selectedGroupId,
                    selectedSubcategoryId: $selectedSubcategoryId,
                    filterType: type,
                    onSelect: {}
                )
            }
            .task { if let t = transactionToEdit { await loadDetails(id: t.id) } }
        }
    }
    
    func loadDetails(id: Int) async {
        isLoading = true
        guard let token = authManager.token else { errorMessage = "Нет токена"; showErrorAlert = true; isLoading = false; return }
        
        let url = "\(authManager.baseURL)/budget/transactions/\(id)"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { throw NSError(domain: "Server", code: -1) }
            
            let tx = try JSONDecoder().decode(BudgetView.Transaction.self, from: data)
            
            DispatchQueue.main.async {
                self.amount = String(format: "%.2f", abs(tx.amount))
                self.type = tx.transaction_type
                self.note = tx.description ?? ""
                
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: tx.date) { self.date = d }
                
                if let gid = findGroupId(forSubcategoryId: tx.category_id, in: categoryGroups) {
                    self.selectedGroupId = gid
                    self.selectedSubcategoryId = tx.category_id
                }
                self.isLoading = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.isAmountFocused = true }
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Ошибка загрузки: \(error.localizedDescription)"
                self.showErrorAlert = true
                self.isLoading = false
            }
        }
    }
    
    func submit() {
        guard let val = Double(amount.replacingOccurrences(of: ",", with: ".")) else { errorMessage = "Неверная сумма"; showErrorAlert = true; return }
        let finalAmt = type == "expense" ? -abs(val) : abs(val)
        
        // ЛОГИКА ЗАГЛУШКИ:
        // Если пользователь ничего не выбрал (selectedSubcategoryId == nil), подставляем ID заглушки.
        // Но только если заглушка существует (ID != 999).
        var finalCatId: Int? = selectedSubcategoryId
        
        if finalCatId == nil {
            if DEFAULT_SUBCATEGORY_ID != 999 {
                finalCatId = DEFAULT_SUBCATEGORY_ID
            } else {
                errorMessage = "Ошибка конфигурации: не настроена категория-заглушка. Обратитесь к администратору."
                showErrorAlert = true
                return
            }
        }
        
        isSaving = true
        onSave(transactionToEdit?.id, finalAmt, type, finalCatId, note, date)
    }
}
