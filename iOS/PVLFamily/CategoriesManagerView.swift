import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categories: [BudgetView.Category]
    @State private var showingAddSheet = false
    @State private var editingCategory: BudgetView.Category? = nil
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Категории")) {
                    ForEach(categories) { cat in
                        CategoryRowView(category: cat, level: 0, onEdit: { editingCategory = cat }, onDelete: deleteCategory)
                        if let children = cat.children {
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
    }
    
    func deleteCategory(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                // Перезагружаем список категорий
                var r = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
                r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: r) { data, _, _ in
                    guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
                    DispatchQueue.main.async { categories = list }
                }.resume()
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
                // Перезагрузка списка
                var r = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
                r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: r) { data, _, _ in
                    guard let data = data, let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
                    DispatchQueue.main.async { categories = list }
                }.resume()
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
                Text("↳")
                    .foregroundColor(.gray)
            }
            VStack(alignment: .leading) {
                Text(category.name)
                    .font(.body)
                Text(category.type)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            
            // Кнопка редактирования
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.blue)
            }
            
            // Кнопка удаления (исправлено)
            Button(role: .destructive, action: {
                onDelete(category.id)
            }) {
                Image(systemName: "trash")
            }
        }
        .padding(.leading, CGFloat(level * 20))
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
    
    var rootCategories: [BudgetView.Category] {
        categories.filter { $0.parent_id == nil && $0.type == type }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Тип", selection: $type) {
                    Text("Расход").tag("expense")
                    Text("Доход").tag("income")
                    Text("Перевод").tag("transfer")
                }
                Picker("Родительская категория (необязательно)", selection: $parentId) {
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
