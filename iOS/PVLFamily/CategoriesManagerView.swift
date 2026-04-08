import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categories: [BudgetView.Category]
    
    // Состояния UI
    @State private var showingAddSheet = false
    @State private var editingCategory: BudgetView.Category? = nil
    @State private var showHiddenToggle = false
    
    // Состояния для обработки ошибок и загрузки
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isSaving = false
    
    // Плоский список для отображения
    var displayList: [FlatCategoryItem] {
        return buildFlatList(from: categories, showHidden: showHiddenToggle)
    }
    
    var body: some View {
        Group {
            if isLoading && categories.isEmpty {
                ProgressView("Загрузка категорий...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
            }
        }
        .navigationTitle("Управление")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    guard !isSaving else { return }
                    editingCategory = nil; showingAddSheet = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .opacity(isSaving ? 0.5 : 1.0)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CategoryForm(
                isPresented: $showingAddSheet,
                categories: categories,
                editCat: editingCategory,
                onSave: saveCat,
                isSaving: isSaving
            )
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            if categories.isEmpty {
                loadCats()
            }
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                loadCats()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    continuation.resume()
                }
            }
        }
    }
    
    // --- ЛОГИКА ---
    
    func handleEdit(_ cat: BudgetView.Category) {
        guard !isSaving else { return }
        editingCategory = cat
        showingAddSheet = true
    }
    
    func handleAction(_ action: CategoryAction, for cat: BudgetView.Category) {
        guard !isSaving else { return }
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
    
    func loadCats() {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isLoading = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при загрузке категорий"
                    showErrorAlert = true
                    return
                }
                
                guard let data = data else {
                    errorMessage = "Пустой ответ от сервера"
                    showErrorAlert = true
                    return
                }
                
                do {
                    let list = try JSONDecoder().decode([BudgetView.Category].self, from: data)
                    self.categories = list
                } catch {
                    errorMessage = "Ошибка обработки данных: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func hideCategory(_ cat: BudgetView.Category) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)/hide")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data()
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при скрытии категории"
                    showErrorAlert = true
                    return
                }
                
                loadCats()
            }
        }.resume()
    }
    
    func unhideCategory(_ cat: BudgetView.Category) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)/unhide")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data()
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 400 {
                        // Специфичная ошибка: родитель скрыт
                        // Пытаемся найти имя родителя, если оно есть в локальном кэше
                        var parentName = "родитель"
                        if let pid = cat.parent_id,
                           let parent = self.categories.first(where: { $0.id == pid }) {
                            parentName = parent.name
                        }
                        self.errorMessage = "Нельзя восстановить эту категорию, потому что её родитель («\(parentName)») всё ещё скрыт. Сначала восстановите родителя."
                        self.showErrorAlert = true
                        return
                    }
                    
                    if !(200...299).contains(http.statusCode) {
                        self.errorMessage = "Ошибка сервера (код \(http.statusCode))"
                        self.showErrorAlert = true
                        return
                    }
                }
                
                loadCats()
            }
        }.resume()
    }
    
    func deleteCategoryForever(_ cat: BudgetView.Category) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        // Оптимистичное удаление
        let originalCategories = categories
        categories.removeAll { $0.id == cat.id }
        
        isSaving = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/categories/\(cat.id)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if let error = error {
                    // Откат
                    self.categories = originalCategories
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    // Откат
                    self.categories = originalCategories
                    errorMessage = "Ошибка сервера при удалении"
                    showErrorAlert = true
                    return
                }
                
                loadCats()
            }
        }.resume()
    }
    
    func saveCat(name: String, type: String, parentId: Int?) {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
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
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                
                if let error = error {
                    errorMessage = "Ошибка сети: \(error.localizedDescription)"
                    showErrorAlert = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    errorMessage = "Ошибка сервера при сохранении"
                    showErrorAlert = true
                    return
                }
                
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
    let isSaving: Bool
    
    @State private var name: String = ""
    @State private var type: String = "expense"
    @State private var parentId: Int? = nil
    
    init(isPresented: Binding<Bool>, categories: [BudgetView.Category], editCat: BudgetView.Category?, onSave: @escaping (String, String, Int?) -> Void, isSaving: Bool = false) {
        self._isPresented = isPresented
        self.categories = categories
        self.editCat = editCat
        self.onSave = onSave
        self.isSaving = isSaving
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
                    .disabled(isSaving)
                Picker("Тип", selection: $type) {
                    Text("Расход").tag("expense")
                    Text("Доход").tag("income")
                }
                .disabled(isSaving)
                Picker("Родитель", selection: $parentId) {
                    Text("Нет (корневая)").tag(nil as Int?)
                    ForEach(roots) { cat in
                        Text(cat.name).tag(cat.id as Int?)
                    }
                }
                .disabled(isSaving)
            }
            .navigationTitle(editCat == nil ? "Новая" : "Ред.")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { isPresented = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        guard !name.isEmpty else { return };
                        onSave(name, type, parentId)
                    }
                    .disabled(isSaving)
                    .overlay(
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            }
                        }
                    )
                }
            }
        }
    }
}
