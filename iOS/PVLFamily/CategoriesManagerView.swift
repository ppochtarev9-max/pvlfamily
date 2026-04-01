import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categories: [BudgetView.Category]
    @State private var showingAddSheet = false
    @State private var editingCategory: BudgetView.Category? = nil
    
    var body: some View {
        List {
            Section(header: Text("Категории")) {
                // Находим только корневые категории
                let roots = categories.filter { $0.parent_id == nil }
                ForEach(roots) { root in
                    CategoryTreeNode(category: root, allCategories: categories, onEdit: { editingCategory = root }, onDelete: deleteCat)
                }
            }
        }
        .navigationTitle("Управление")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { editingCategory = nil; showingAddSheet = true }) { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryForm(isPresented: $showingAddSheet, categories: categories, editCat: editingCategory, onSave: saveCat)
        }
        .onAppear { loadCats() }
    }
    
    func loadCats() {
        guard let token = authManager.token else { return }
        let url = "\(authManager.baseURL)/budget/categories"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
            DispatchQueue.main.async { self.categories = list }
        }.resume()
    }
    
    func deleteCat(id: Int) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { loadCats() }
        }.resume()
    }
    
    func saveCat(name: String, type: String, parentId: Int?) {
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
                loadCats()
            }
        }.resume()
    }
}

// Рекурсивный компонент для отрисовки дерева
struct CategoryTreeNode: View {
    let category: BudgetView.Category
    let allCategories: [BudgetView.Category]
    let onEdit: () -> Void
    let onDelete: (Int) -> Void
    
    var children: [BudgetView.Category] {
        allCategories.filter { $0.parent_id == category.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Строка самой категории
            HStack {
                VStack(alignment: .leading) {
                    Text(category.name).font(.body).fontWeight(.medium)
                    Text(category.type).font(.caption).foregroundColor(.gray)
                }
                Spacer()
                Button(action: onEdit) { Image(systemName: "pencil").foregroundColor(.blue) }
                Button(role: .destructive, action: { onDelete(category.id) }) { Image(systemName: "trash") }
            }
            
            // Рекурсивный вызов для детей
            if !children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(children) { child in
                        CategoryTreeNode(category: child, allCategories: allCategories, onEdit: onEdit, onDelete: onDelete)
                            .padding(.leading, 20) // Отступ для подкатегорий
                    }
                }
            }
        }
    }
}

struct CategoryForm: View {
    @Binding var isPresented: Bool
    let categories: [BudgetView.Category]
    let editCat: BudgetView.Category?
    let onSave: (String, String, Int?) -> Void
    
    @State private var name: String = ""
    @State private var type: String = "expense"
    @State private var parentId: Int? = nil
    
    init(isPresented: Binding<Bool>, categories: [BudgetView.Category], editCat: BudgetView.Category?, onSave: @escaping (String, String, Int?) -> Void) {
        self._isPresented = isPresented
        self.categories = categories
        self.editCat = editCat
        self.onSave = onSave
        if let c = editCat {
            _name = State(initialValue: c.name)
            _type = State(initialValue: c.type)
            _parentId = State(initialValue: c.parent_id)
        }
    }
    
    var roots: [BudgetView.Category] {
        categories.filter { $0.parent_id == nil && $0.type == type }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Тип", selection: $type) {
                    Text("Расход").tag("expense")
                    Text("Доход").tag("income")
                }
                Picker("Родитель", selection: $parentId) {
                    Text("Нет (корневая)").tag(nil as Int?)
                    ForEach(roots) { cat in
                        Text(cat.name).tag(cat.id as Int?)
                    }
                }
            }
            .navigationTitle(editCat == nil ? "Новая" : "Ред.")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Отмена") { isPresented = false } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { guard !name.isEmpty else { return }; onSave(name, type, parentId) }
                }
            }
        }
    }
}
