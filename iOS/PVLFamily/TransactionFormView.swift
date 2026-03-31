import SwiftUI

struct TransactionFormView: View {
    @Binding var isPresented: Bool
    let categories: [BudgetView.Category]
    let transactionToEdit: BudgetView.Transaction?
    let onSave: (Int?, Double, String, Int, String, Date) -> Void
    let onDelete: (Int) -> Void
    
    @State private var amount: String = ""
    @State private var selectedType: String = "expense"
    @State private var selectedParentId: Int? = nil
    @State private var selectedSubcategoryId: Int? = nil // Выбор подкатегории
    @State private var description: String = ""
    @State private var selectedDate: Date = Date()
    
    // Фильтруем только корневые категории выбранного типа
    var rootCategories: [BudgetView.Category] {
        categories.filter { $0.type == selectedType && $0.parent_id == nil }
    }
    
    // Получаем подкатегории для выбранного родителя
    var subcategories: [BudgetView.Category] {
        guard let parentId = selectedParentId else { return [] }
        // Ищем категорию-родителя в общем списке и берем её детей
        if let parent = categories.first(where: { $0.id == parentId }) {
            return parent.children ?? []
        }
        return []
    }
    
    // Итоговый ID категории для отправки (приоритет у подкатегории)
    var finalCategoryId: Int? {
        if let subId = selectedSubcategoryId {
            return subId
        }
        return selectedParentId
    }
    
    init(isPresented: Binding<Bool>,
         categories: [BudgetView.Category],
         transactionToEdit: BudgetView.Transaction?,
         onSave: @escaping (Int?, Double, String, Int, String, Date) -> Void,
         onDelete: @escaping (Int) -> Void) {
        
        self._isPresented = isPresented
        self.categories = categories
        self.transactionToEdit = transactionToEdit
        self.onSave = onSave
        self.onDelete = onDelete
        
        if let t = transactionToEdit {
            _amount = State(initialValue: String(t.amount))
            _selectedType = State(initialValue: t.transaction_type)
            _description = State(initialValue: t.description ?? "")
            
            // Пытаемся восстановить выбранные категории
            // Находим категорию транзакции в дереве
            func findPath(catId: Int, cats: [BudgetView.Category]) -> (Int?, Int?) {
                for cat in cats {
                    if cat.id == catId {
                        // Если это корень
                        if cat.parent_id == nil {
                            return (cat.id, nil)
                        } else {
                            // Если это ребенок, родителем будет его parent_id
                            return (cat.parent_id, cat.id)
                        }
                    }
                    if let children = cat.children {
                        let res = findPath(catId: catId, cats: children)
                        if res.0 != nil || res.1 != nil {
                            return res
                        }
                    }
                }
                return (nil, nil)
            }
            
            let (pId, sId) = findPath(catId: t.category_id, cats: categories)
            _selectedParentId = State(initialValue: pId)
            _selectedSubcategoryId = State(initialValue: sId)
            
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: t.date) {
                _selectedDate = State(initialValue: date)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Сумма")) {
                    TextField("0.00", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Тип операции")) {
                    Picker("Тип", selection: $selectedType) {
                        Text("Расход").tag("expense")
                        Text("Доход").tag("income")
                        Text("Перевод").tag("transfer")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedType) { _ in
                        selectedParentId = nil
                        selectedSubcategoryId = nil
                    }
                }
                
                Section(header: Text("Категория")) {
                    // 1. Выбор основной категории (Родителя)
                    Picker("Основная категория", selection: $selectedParentId) {
                        Text("Не выбрано").tag(nil as Int?)
                        ForEach(rootCategories) { cat in
                            Text(cat.name).tag(cat.id as Int?)
                        }
                    }
                    
                    // 2. Выбор подкатегории (появляется только если выбран родитель и есть дети)
                    if !subcategories.isEmpty {
                        Picker("Подкатегория", selection: $selectedSubcategoryId) {
                            Text("Без подкатегории (использовать основную)").tag(nil as Int?)
                            ForEach(subcategories) { sub in
                                Text(sub.name).tag(sub.id as Int?)
                            }
                        }
                    } else if selectedParentId != nil {
                        Text("Нет подкатегорий").foregroundColor(.gray).font(.caption)
                    }
                }
                
                Section(header: Text("Дата и время")) {
                    DatePicker("Когда совершена операция:",
                               selection: $selectedDate,
                               displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("Описание")) {
                    TextField("Комментарий", text: $description)
                }
                
                if transactionToEdit != nil {
                    Section {
                        Button("Удалить транзакцию", role: .destructive) {
                            if let id = transactionToEdit?.id {
                                onDelete(id)
                            }
                        }
                    }
                }
            }
            .navigationTitle(transactionToEdit == nil ? "Новая запись" : "Редактирование")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        guard let amt = Double(amount), let catId = finalCategoryId else {
                            return
                        }
                        onSave(transactionToEdit?.id, amt, selectedType, catId, description, selectedDate)
                    }
                    .disabled(amount.isEmpty || finalCategoryId == nil)
                }
            }
        }
    }
}
