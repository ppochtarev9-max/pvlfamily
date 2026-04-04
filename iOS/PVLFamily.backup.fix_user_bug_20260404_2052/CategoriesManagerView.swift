import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categories: [BudgetView.Category]
    @State private var showingAddSheet = false
    @State private var editingCategory: BudgetView.Category? = nil
    
    // Настройки отображения
    @State private var showHiddenToggle = false
    
    // Состояние для алерта ошибки
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // Плоский список для отображения
    var displayList: [FlatCategoryItem] {
        return buildFlatList(from: categories, showHidden: showHiddenToggle)
    }
    
    var body: some View {
        List {
            Section(header: HStack {
                Text("Категории")
                Spacer()
                Toggle(isOn: $showHiddenToggle) {
                    Text(showHiddenToggle ? "Скрытые: ВКЛ" : "Скрытые: ВЫКЛ")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }) {
                ForEach(displayList) { item in
                    CategoryRow(item: item, onEdit: { handleEdit(item.category) }, onAction: { action in
                        handleAction(action, for: item.category)
                    })
                    .padding(.leading, CGFloat(item.level * 20))
                }
            }
        }
        .navigationTitle("Управление")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { editingCategory = nil; showingAddSheet = true }) {
                    Image(systemName: "plus").font(.system(size: 20))
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryForm(isPresented: $showingAddSheet, categories: categories, editCat: editingCategory, onSave: saveCat)
        }
        // Алерт об ошибке (например, если родитель скрыт)
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear { loadCats() }
    }
    
    // --- ЛОГИКА ---
    
    func handleEdit(_ cat: BudgetView.Category) {
        editingCategory = cat
        showingAddSheet = true
    }
    
    func handleAction(_ action: CategoryAction, for cat: BudgetView.Category) {
        switch action {
        case .edit:
            handleEdit(cat)
        case .hide:
            hideCategory(cat)
        case .unhide:
            unhideCategory(cat)
        case .delete:
            deleteCategoryForever(cat)
        }
    }
    
    func hideCategory(_ cat: BudgetView.Category) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)/hide")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data()
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { loadCats() }
        }.resume()
    }
    
    func unhideCategory(_ cat: BudgetView.Category) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)/unhide")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data()
        
        URLSession.shared.dataTask(with: req) { data, resp, error in
            DispatchQueue.main.async {
                if let http = resp as? HTTPURLResponse, http.statusCode == 400 {
                    // Показываем красивый алерт вместо print
                    self.errorMessage = "Нельзя восстановить эту категорию, потому что её родитель («\(cat.name)») всё ещё скрыт. Сначала восстановите родителя."
                    self.showErrorAlert = true
                } else if error != nil {
                    self.errorMessage = "Ошибка сети: \(error!.localizedDescription)"
                    self.showErrorAlert = true
                } else {
                    loadCats()
                }
            }
        }.resume()
    }
    
    func deleteCategoryForever(_ cat: BudgetView.Category) {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { loadCats() }
        }.resume()
    }
    
    func loadCats() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let list = try? JSONDecoder().decode([BudgetView.Category].self, from: data) else { return }
            DispatchQueue.main.async {
                self.categories = list
            }
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

// --- МОДЕЛИ И СПИСКИ ---

enum CategoryAction {
    case edit
    case hide
    case unhide
    case delete
}

struct FlatCategoryItem: Identifiable {
    let id = UUID()
    let category: BudgetView.Category
    let level: Int
}

func buildFlatList(from categories: [BudgetView.Category], showHidden: Bool) -> [FlatCategoryItem] {
    var lookup: [Int: [BudgetView.Category]] = [:]
    var roots: [BudgetView.Category] = []
    
    for cat in categories {
        if let pid = cat.parent_id {
            if lookup[pid] == nil { lookup[pid] = [] }
            lookup[pid]?.append(cat)
        } else {
            roots.append(cat)
        }
    }
    
    var result: [FlatCategoryItem] = []
    
    func traverse(_ cats: [BudgetView.Category], level: Int) {
        for cat in cats {
            if cat.is_hidden == true && !showHidden {
                continue
            }
            result.append(FlatCategoryItem(category: cat, level: level))
            if let children = lookup[cat.id] {
                traverse(children, level: level + 1)
            }
        }
    }
    
    traverse(roots, level: 0)
    return result
}

// --- ЯЧЕЙКА С МЕНЮ ---
// Исправлено: используем label с пустым заголовком для Menu, чтобы избежать багов SwiftUI

struct CategoryRow: View {
    let item: FlatCategoryItem
    let onEdit: () -> Void
    let onAction: (CategoryAction) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text(item.category.name)
                    .font(.body)
                    .strikethrough(item.category.is_hidden == true)
                    .foregroundColor(item.category.is_hidden == true ? .gray : .primary)
                Text(item.category.type)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            
            // Используем Menu с явным Label
            Menu {
                Button(action: { onAction(.edit) }) {
                    Label("Редактировать", systemImage: "pencil")
                }
                
                if item.category.is_hidden == true {
                    Button(action: { onAction(.unhide) }) {
                        Label("Вернуть в список", systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button(action: { onAction(.hide) }) {
                        Label("Скрыть", systemImage: "eye.slash")
                    }
                }
                
                Divider()
                
                Button(role: .destructive, action: { onAction(.delete) }) {
                    Label("Удалить навсегда", systemImage: "trash")
                }
            } label: {
                // Явная кнопка-обертка для стабильности
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
    }
}

// --- ФОРМА ---

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
