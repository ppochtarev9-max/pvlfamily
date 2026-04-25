import SwiftUI

struct CategoriesManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var categoryGroups: [BudgetView.CategoryGroup]
    
    // Состояния UI
    @State private var showingAddGroupSheet = false
    @State private var editingGroup: BudgetView.CategoryGroup?
    @State private var showHiddenToggle = false
    @State private var navigationSelection: Int? // Храним ID группы, а не объект
    
    // Состояния для обработки ошибок и загрузки
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isSaving = false
    
    var displayList: [BudgetView.CategoryGroup] {
        if showHiddenToggle {
            return categoryGroups.sorted { $0.name < $1.name }
        } else {
            return categoryGroups.filter { !$0.is_hidden }.sorted { $0.name < $1.name }
        }
    }
    
    var body: some View {
        Group {
            if isLoading && categoryGroups.isEmpty {
                ProgressView("Загрузка...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: HStack {
                        Text("Категории").font(.headline)
                        Spacer()
                        Button(action: {
                            print("👆 [UI] Toggle скрытых нажат. Было: \(showHiddenToggle)")
                            showHiddenToggle.toggle()
                        }) {
                            Image(systemName: showHiddenToggle ? "eye.fill" : "eye.slash")
                                .foregroundStyle(showHiddenToggle ? FamilyAppStyle.accent : Color.gray)
                                .font(.system(size: 18))
                        }
                    }) {
                        ForEach(displayList) { group in
                            GroupRow(group: group, onNavigate: {
                                navigationSelection = group.id // Передаем ID
                            }, onEdit: {
                                editingGroup = group
                                showingAddGroupSheet = true
                            }, onHide: {
                                toggleHideGroup(group)
                            }, onDelete: {
                                deleteGroupForever(group)
                            })
                        }
                        
                        Button(action: {
                            editingGroup = nil
                            showingAddGroupSheet = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(FamilyAppStyle.accent).font(.title2)
                                Text("Добавить новую категорию").fontWeight(.semibold).foregroundStyle(FamilyAppStyle.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .pvlFormScreenStyle()
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("Категории")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    guard !isSaving else { return }
                    editingGroup = nil; showingAddGroupSheet = true
                }) {
                    Image(systemName: "plus").font(.system(size: 22)).opacity(isSaving ? 0.5 : 1.0)
                }
            }
        }
        .sheet(isPresented: $showingAddGroupSheet) {
            CategoryGroupForm(isPresented: $showingAddGroupSheet, editGroup: editingGroup, onSave: saveGroup, isSaving: isSaving)
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: { Text(errorMessage) }
        .navigationDestination(item: $navigationSelection) { selectedGroupId in
            // Передаем ID, а внутри экран сам найдет актуальные данные
            SubCategoryListView(
                groupId: selectedGroupId,
                groups: $categoryGroups,
                onError: { msg in errorMessage = msg; showErrorAlert = true },
                isLoading: $isSaving
            )
        }
        .onAppear {
            if categoryGroups.isEmpty { loadGroups() }
        }
        .refreshable {
            await withCheckedContinuation { continuation in
                loadGroups()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { continuation.resume() }
            }
        }
    }
    
    // --- ЛОГИКА ГРУПП ---
    
    func loadGroups() {
        print("📡 [Network] GET /budget/groups")
        guard let token = authManager.token else { return }
        isLoading = true
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/groups")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error { print("❌ Error: \(error)"); return }
                guard let httpResponse = response as? HTTPURLResponse else { return }
                print("📥 [Network] Status: \(httpResponse.statusCode)")
                
                if (200...299).contains(httpResponse.statusCode), let data = data {
                    do {
                        let list = try JSONDecoder().decode([BudgetView.CategoryGroup].self, from: data)
                        self.categoryGroups = list
                        print("✅ Loaded \(list.count) groups")
                        // Логируем состояние первой группы для проверки
                        if let first = list.first {
                            print("🔍 Debug First Group: \(first.name), hidden: \(first.is_hidden), subs count: \(first.subcategories.count)")
                            if let firstSub = first.subcategories.first {
                                print("   🔍 Debug First Sub: \(firstSub.name), hidden: \(firstSub.is_hidden)")
                            }
                        }
                    } catch { print("❌ Decode Error: \(error)") }
                }
            }
        }.resume()
    }
    
    func toggleHideGroup(_ group: BudgetView.CategoryGroup) {
        guard let token = authManager.token else { return }
        isSaving = true
        
        let urlStr = group.is_hidden
            ? "\(authManager.baseURL)/budget/groups/\(group.id)/unhide"
            : "\(authManager.baseURL)/budget/groups/\(group.id)?force=false"
        let method = group.is_hidden ? "POST" : "DELETE"
        
        print("📡 [Network] \(method) \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if group.is_hidden {
             req.setValue("application/json", forHTTPHeaderField: "Content-Type")
             req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ No response")
                    errorMessage = "Нет ответа"; showErrorAlert = true; return
                }
                print("📥 [Network] Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("✅ Group visibility toggled. Reloading...")
                    loadGroups() // Полная перезагрузка
                } else {
                    if let data = data, let errStr = String( data: data, encoding: .utf8) {
                        print("❌ Server Error: \(errStr)")
                        errorMessage = "Ошибка: \(errStr)"
                    } else {
                        errorMessage = "Ошибка сервера (\(httpResponse.statusCode))"
                    }
                    showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func deleteGroupForever(_ group: BudgetView.CategoryGroup) {
        guard let token = authManager.token else { return }
        isSaving = true
        let urlStr = "\(authManager.baseURL)/budget/groups/\(group.id)?force=true"
        print("📡 [Network] DELETE \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                isSaving = false
                guard let httpResponse = response as? HTTPURLResponse else { return }
                print("📥 Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 400 {
                    errorMessage = "Есть транзакции!"; showErrorAlert = true; return
                }
                if httpResponse.statusCode == 200 {
                    loadGroups()
                } else {
                    errorMessage = "Ошибка удаления"; showErrorAlert = true
                }
            }
        }.resume()
    }
    
    func saveGroup(name: String, type: String) {
        guard let token = authManager.token else { return }
        isSaving = true
        let urlStr = editingGroup != nil
            ? "\(authManager.baseURL)/budget/groups/\(editingGroup!.id)"
            : "\(authManager.baseURL)/budget/groups"
        let method = editingGroup != nil ? "PUT" : "POST"
        
        print("📡 [Network] \(method) \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "type": type, "is_hidden": false]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                isSaving = false
                guard let httpResponse = response as? HTTPURLResponse else { return }
                print("📥 Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    showingAddGroupSheet = false; editingGroup = nil; loadGroups()
                } else {
                    errorMessage = "Ошибка сохранения"; showErrorAlert = true
                }
            }
        }.resume()
    }
}

// --- ROWS ---

struct GroupRow: View {
    let group: BudgetView.CategoryGroup
    let onNavigate: () -> Void
    let onEdit: () -> Void
    let onHide: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(group.type == "income" ? Color.green.opacity(0.15) : FamilyAppStyle.accent.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: group.type == "income" ? "arrow.down.left.and.arrow.up.right" : "cart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(group.type == "income" ? Color.green : FamilyAppStyle.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name).font(.system(size: 17, weight: .semibold)).foregroundColor(group.is_hidden ? .gray : .primary).strikethrough(group.is_hidden)
                HStack(spacing: 6) {
                    Text("\(group.subcategories.count) подкатегорий").font(.system(size: 13, weight: .medium)).foregroundStyle(FamilyAppStyle.accent)
                    if group.is_hidden { Text("• Скрыто").font(.caption).foregroundColor(.orange) }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundColor(.gray.opacity(0.5))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onNavigate() }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") }
            Button { onHide() } label: { Label(group.is_hidden ? "Вернуть" : "Скрыть", systemImage: group.is_hidden ? "eye" : "eye.slash") }
                .tint(group.is_hidden ? .green : .orange)
            Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") }.tint(FamilyAppStyle.accent)
        }
    }
}

// --- ЭКРАН ПОДКАТЕГОРИЙ (ИСПРАВЛЕННЫЙ) ---

struct SubCategoryListView: View {
    let groupId: Int // Храним только ID
    @Binding var groups: [BudgetView.CategoryGroup] // Ссылка на общий массив
    let onError: (String) -> Void
    @Binding var isLoading: Bool
    
    @State private var showingAddSubSheet = false
    @State private var editingSub: BudgetView.SubCategory?
    @State private var showHiddenToggle = false
    @EnvironmentObject var authManager: AuthManager
    
    // Вычисляемое свойство: всегда берет свежие данные из общего массива
    var currentGroup: BudgetView.CategoryGroup? {
        groups.first { $0.id == groupId }
    }
    
    var filteredSubs: [BudgetView.SubCategory] {
        guard let g = currentGroup else { return [] }
        if showHiddenToggle {
            return g.subcategories.sorted { $0.name < $1.name }
        } else {
            return g.subcategories.filter { !$0.is_hidden }.sorted { $0.name < $1.name }
        }
    }
    
    var body: some View {
        Group {
            if let group = currentGroup {
                List {
                    Section(header: HStack {
                        Text("Подкатегории: \(group.name)").font(.headline)
                        Spacer()
                        Button(action: {
                            print("👁️ [SUB] Toggle скрытых нажат. Было: \(showHiddenToggle)")
                            showHiddenToggle.toggle()
                        }) {
                            Image(systemName: showHiddenToggle ? "eye.fill" : "eye.slash")
                                .foregroundStyle(showHiddenToggle ? FamilyAppStyle.accent : Color.gray)
                        }
                    }) {
                        if filteredSubs.isEmpty {
                            Text("Нет подкатегорий").font(.caption).foregroundColor(.secondary).italic()
                        } else {
                            ForEach(filteredSubs, id: \.id) { sub in
                                // Логируем отрисовку каждой ячейки
                                //print("📱 [ROW] Отрисовка: \(sub.name), hidden: \(sub.is_hidden)")
                                
                                SubCategoryRow(sub: sub, onEdit: {
                                    editingSub = sub
                                    showingAddSubSheet = true
                                }, onHide: {
                                    toggleHideSub(sub)
                                }, onDelete: {
                                    deleteSubForever(sub)
                                })
                            }
                        }
                        
                        Button(action: { editingSub = nil; showingAddSubSheet = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill").foregroundStyle(FamilyAppStyle.accent)
                                Text("Добавить подкатегорию").fontWeight(.medium).foregroundStyle(FamilyAppStyle.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                        }.listRowSeparator(.hidden)
                    }
                }
                .listStyle(.insetGrouped)
                .pvlFormScreenStyle()
                .navigationTitle("Подкатегории")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showingAddSubSheet) {
                    SubCategoryForm(isPresented: $showingAddSubSheet, groupId: group.id, editSub: editingSub, onSave: saveSub, isLoading: $isLoading)
                }
            } else {
                ProgressView("Загрузка группы...")
            }
        }
    }
    
    func toggleHideSub(_ sub: BudgetView.SubCategory) {
        isLoading = true
        guard let token = authManager.token else { return }
        
        let urlStr = sub.is_hidden
            ? "\(authManager.baseURL)/budget/subcategories/\(sub.id)/unhide"
            : "\(authManager.baseURL)/budget/subcategories/\(sub.id)?force=false"
        let method = sub.is_hidden ? "POST" : "DELETE"
        
        print("📡 [SUB] \(method) \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if sub.is_hidden {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        }
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [SUB] No response"); onError("Нет ответа"); return
                }
                print("📥 [SUB] Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("✅ [SUB] Toggled OK. Перезагружаем список групп...")
                    // Ключевой момент: перезагружаем ВЕСЬ список групп, чтобы обновить вложенную структуру
                    loadGroupsFull()
                } else {
                    if let data = data, let err = String( data: data, encoding: .utf8) {
                        print("❌ [SUB] Error: \(err)")
                        onError(err)
                    } else {
                        onError("Ошибка (\(httpResponse.statusCode))")
                    }
                }
            }
        }.resume()
    }
    
    func deleteSubForever(_ sub: BudgetView.SubCategory) {
        isLoading = true
        guard let token = authManager.token else { return }
        let urlStr = "\(authManager.baseURL)/budget/subcategories/\(sub.id)?force=true"
        print("📡 [SUB] DELETE \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let httpResponse = response as? HTTPURLResponse else { return }
                print("📥 [SUB] Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 400 { onError("Есть транзакции"); return }
                if httpResponse.statusCode == 200 {
                    print("✅ [SUB] Deleted OK. Перезагружаем список групп...")
                    loadGroupsFull()
                }
                else { onError("Ошибка удаления") }
            }
        }.resume()
    }
    
    func saveSub(name: String) {
        isLoading = true
        guard let token = authManager.token else { return }
        
        var urlStr = "\(authManager.baseURL)/budget/subcategories"
        var method = "POST"
        if editingSub != nil {
            urlStr = "\(authManager.baseURL)/budget/subcategories/\(editingSub!.id)"
            method = "PUT"
        }
        print("📡 [SUB] \(method) \(urlStr)")
        
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "group_id": groupId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let httpResponse = response as? HTTPURLResponse else { return }
                print("📥 [SUB] Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    showingAddSubSheet = false; editingSub = nil
                    print("✅ [SUB] Saved OK. Перезагружаем список групп...")
                    loadGroupsFull()
                } else { onError("Ошибка сохранения") }
            }
        }.resume()
    }
    
    // Функция полной перезагрузки списка групп
    func loadGroupsFull() {
        guard let token = authManager.token else { return }
        var req = URLRequest(url: URL(string: "\(authManager.baseURL)/budget/groups")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let data = data,
               let list = try? JSONDecoder().decode([BudgetView.CategoryGroup].self, from: data) {
                DispatchQueue.main.async {
                    self.groups = list
                    print("✅ [UPDATE] Список групп обновлен (\(list.count) шт). Экран подкатегорий перерисуется автоматически.")
                    
                    // Проверка конкретной группы
                    if let updatedGroup = list.first(where: { $0.id == self.groupId }) {
                        let hiddenCount = updatedGroup.subcategories.filter { $0.is_hidden }.count
                        print("🔍 [CHECK] Группа \(updatedGroup.name): всего подкатегорий \(updatedGroup.subcategories.count), скрыто: \(hiddenCount)")
                    }
                }
            } else {
                print("❌ [UPDATE] Не удалось обновить список групп")
                onError("Не удалось обновить данные")
            }
        }.resume()
    }
}

// --- ОСТАЛЬНЫЕ ВИДЫ (БЕЗ ИЗМЕНЕНИЙ) ---

struct SubCategoryRow: View {
    let sub: BudgetView.SubCategory
    let onEdit: () -> Void
    let onHide: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(sub.is_hidden ? Color.gray : FamilyAppStyle.accent).frame(width: 4, height: 40).cornerRadius(2)
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.name).font(.system(size: 16, weight: .medium)).foregroundColor(sub.is_hidden ? .gray : .primary).strikethrough(sub.is_hidden)
                if sub.is_hidden { Text("Скрыта").font(.caption).foregroundColor(.gray) }
            }
            Spacer()
            Image(systemName: sub.is_hidden ? "eye.slash.fill" : "checkmark.circle.fill").foregroundColor(sub.is_hidden ? .gray : .green).font(.title3)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { onDelete() } label: { Label("Удалить", systemImage: "trash") }
            Button { onHide() } label: { Label(sub.is_hidden ? "Вернуть" : "Скрыть", systemImage: sub.is_hidden ? "eye" : "eye.slash") }
                .tint(sub.is_hidden ? .green : .orange)
            Button { onEdit() } label: { Label("Изменить", systemImage: "pencil") }.tint(FamilyAppStyle.accent)
        }
    }
}

struct CategoryGroupForm: View {
    @Binding var isPresented: Bool
    let editGroup: BudgetView.CategoryGroup?
    let onSave: (String, String) -> Void
    let isSaving: Bool
    @State private var name: String = ""
    @State private var type: String = "expense"
    
    init(isPresented: Binding<Bool>, editGroup: BudgetView.CategoryGroup?, onSave: @escaping (String, String) -> Void, isSaving: Bool = false) {
        self._isPresented = isPresented; self.editGroup = editGroup; self.onSave = onSave; self.isSaving = isSaving
        if let g = editGroup { _name = State(initialValue: g.name); _type = State(initialValue: g.type) }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name).disabled(isSaving)
                Picker("Тип", selection: $type) { Text("Расход").tag("expense"); Text("Доход").tag("income") }
                    .pickerStyle(.segmented).disabled(isSaving || editGroup != nil)
            }
            .pvlFormScreenStyle()
            .tint(FamilyAppStyle.accent)
            .navigationTitle(editGroup == nil ? "Новая" : "Ред.")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { guard !name.isEmpty else { return }; onSave(name, type) }.disabled(isSaving || name.isEmpty) }
            }
        }
    }
}

struct SubCategoryForm: View {
    @Binding var isPresented: Bool
    let groupId: Int
    let editSub: BudgetView.SubCategory?
    let onSave: (String) -> Void
    @Binding var isLoading: Bool
    @State private var name: String = ""
    
    init(isPresented: Binding<Bool>, groupId: Int, editSub: BudgetView.SubCategory?, onSave: @escaping (String) -> Void, isLoading: Binding<Bool>) {
        self._isPresented = isPresented; self.groupId = groupId; self.editSub = editSub; self.onSave = onSave; self._isLoading = isLoading
        if let s = editSub { _name = State(initialValue: s.name) }
    }
    
    var body: some View {
        NavigationStack {
            Form { TextField("Название", text: $name).autocapitalization(.words) }
            .pvlFormScreenStyle()
            .tint(FamilyAppStyle.accent)
            .navigationTitle(editSub == nil ? "Новая" : "Ред.")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { guard !name.isEmpty else { return }; onSave(name) }.disabled(isLoading || name.isEmpty) }
            }
        }
    }
}
