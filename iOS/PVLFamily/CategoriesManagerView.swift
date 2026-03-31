import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categories: [BudgetView.Category]
    @State private var showingAddSheet = false
    @State private var editingCategory: BudgetView.Category? = nil
    
    // Вычисляемое свойство для построения дерева
    var treeCategories: [BudgetView.Category] {
        buildTree(from: categories)
    }
    
    var body: some View {
        List {
            Section(header: Text("Категории")) {
                ForEach(treeCategories) { cat in
                    CategoryRowView(category: cat, level: 0, onEdit: { editingCategory = cat }, onDelete: deleteCategory)
                    
                    // Рекурсивное отображение детей
                    if let children = cat.children, !children.isEmpty {
                        ForEach(children) { child in
                            CategoryRowView(category: child, level: 1, onEdit: { editingCategory = child }, onDelete: deleteCategory)
                        }
                    }
                }
            }
        }
        .navigationTitle("Управление категориями")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { editingCategory = nil; showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryFormView(
                isPresented: $showingAddSheet,
                categories: categories,
                categoryToEdit: editingCategory,
                onSave: saveCategory
            )
        }
    }
    
    // Надежное построение дерева
    func buildTree(from flat: [BudgetView.Category]) -> [BudgetView.Category] {
        var lookup: [Int: BudgetView.Category] = [:]
        var roots: [BudgetView.Category] = []
        
        // 1. Создаем копии всех элементов с пустыми детьми
        for item in flat {
            var newItem = item
            newItem.children = []
            lookup[item.id] = newItem
        }
        
        // 2. Распределяем по родителям
        for item in flat {
            if let parentId = item.parent_id {
                // Если есть родитель, добавляем себя в его дети
                if var parent = lookup[parentId] {
                    if var child = lookup[item.id] {
                        parent.children?.append(child)
                        lookup[parentId] = parent
                    }
                }
            } else {
                // Если родителя нет, это корень
                if let root = lookup[item.id] {
                    roots.append(root)
                }
            }
        }
        return roots
    }
    
    func deleteCategory(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                reloadCategories()
            }
        }.resume()
    }
    
    func saveCategory(name: String, type: String, parentId: Int?) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.httpMethod = (editingCategory != nil) ? "PUT" : "POST"
        
        if let eid = editingCategory?.id {
            req.url = URL(string: "\(authManager.baseURL)/budget/categories/\(eid)")
        }
        
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["name": name, "type": type]
        if let pid = parentId { body["parent_id"] = pid }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                showingAddSheet = false
                editingCategory = nil
                // ПЕРЕЗАГРУЖАЕМ СПИСОК, чтобы увидеть изменения
                reloadCategories()
            }
        }.resume()
    }
    
    func reloadCategories() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
            DispatchQueue.main.async {
                self.categories = list
            }
        }.resume()
    }
}

struct CategoryRowView: View {
    let category: BudgetView.Category
    let level: Int
    let onEdit: () -> Void
    let onDelete: (Int) -> Void
    
    var body: some View {
        HStack {
            if level > 0 {
                Text("↳").foregroundColor(.gray)
            }
            VStack(alignment: .leading) {
                Text(category.name).font(.body)
                Text(category.type).font(.caption).foregroundColor(.gray)
            }
            Spacer()
            
            Button(action: onEdit) {
                Image(systemName: "pencil").foregroundColor(.blue)
            }
            
            Button(role: .destructive, action: { onDelete(category.id) }) {
                Image(systemName: "trash")
            }
        }
        .padding(.leading, CGFloat(level * 20))
        .contentShape(Rectangle()) // Чтобы свайп работал, но клик нет
    }
}

struct CategoryFormView: View {
    @Binding var isPresented: Bool
    let categories: [BudgetView.Category]
    let categoryToEdit: BudgetView.Category?
    let onSave: (String, String, Int?) -> Void
    
    @State private var name: String = ""
    @State private var type: String = "expense"
    @State private var parentId: Int? = nil
    
    init(isPresented: Binding<Bool>, categories: [BudgetView.Category], categoryToEdit: BudgetView.Category?, onSave: @escaping (String, String, Int?) -> Void) {
        self._isPresented = isPresented
        self.categories = categories
        self.categoryToEdit = categoryToEdit
        self.onSave = onSave
        
        if let c = categoryToEdit {
            _name = State(initialValue: c.name)
            _type = State(initialValue: c.type)
            _parentId = State(initialValue: c.parent_id)
        }
    }
    
    // Показываем только корни того же типа, что и создаваемая категория
    var rootCategories: [BudgetView.Category] {
        categories.filter { $0.parent_id == nil && $0.type == type }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                
                Picker("Тип операции", selection: $type) {
                    Text("Расход").tag("expense")
                    Text("Доход").tag("income")
                }
                .onChange(of: type) { oldValue, newValue in
                    // При смене типа сбрасываем родителя, если он не подходит
                    if let pid = parentId,
                       let parent = categories.first(where: { $0.id == pid }),
                       parent.type != newValue {
                        parentId = nil
                    }
                }
                
                Picker("Родительская категория", selection: $parentId) {
                    Text("Нет (корневая)").tag(nil as Int?)
                    ForEach(rootCategories) { cat in
                        Text(cat.name).tag(cat.id as Int?)
                    }
                }
            }
            .navigationTitle(categoryToEdit == nil ? "Новая категория" : "Редактировать")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { isPresented = false } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        guard !name.isEmpty else { return }
                        onSave(name, type, parentId)
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
