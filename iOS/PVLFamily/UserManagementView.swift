import SwiftUI

struct UserManagementView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var users: [AdminUserRow] = []
    @State private var isLoading = false
    @State private var showEditor = false
    @State private var editingUser: AdminUserRow?
    @State private var deletingUser: AdminUserRow?
    @State private var showDeleteAlert = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        List {
            if isLoading && users.isEmpty {
                ProgressView("Загрузка пользователей...")
            }
            ForEach(users) { user in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.name)
                            .font(.headline)
                        if user.is_admin {
                            Text("ADMIN")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Circle()
                            .fill(user.is_active ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Text(user.must_reset_password ? "Требуется смена пароля" : "Пароль актуален")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Изменить") {
                        editingUser = user
                        showEditor = true
                    }
                    .tint(FamilyAppStyle.accent)
                    if !user.is_admin {
                        Button("Удалить", role: .destructive) {
                            deletingUser = user
                            showDeleteAlert = true
                        }
                    }
                }
            }
        }
        .background(FamilyAppStyle.screenBackground)
        .scrollContentBackground(.hidden)
        .navigationTitle("Пользователи")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingUser = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            AdminUserEditorSheet(existing: editingUser) { name, password, isActive, mustReset in
                saveUser(name: name, password: password, isActive: isActive, mustReset: mustReset)
            }
            .environmentObject(authManager)
        }
        .alert("Удалить пользователя?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                guard let deletingUser else { return }
                deleteUser(deletingUser.id)
            }
        } message: {
            Text("Действие нельзя отменить")
        }
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .onAppear(perform: reloadUsers)
    }

    private func reloadUsers() {
        isLoading = true
        authManager.loadUsers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.users = authManager.users.compactMap(AdminUserRow.init(dict:))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.isLoading = false
        }
    }

    private func saveUser(name: String, password: String, isActive: Bool, mustReset: Bool) {
        if let editingUser {
            let passwordToSend: String? = password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : password
            authManager.updateUserByAdmin(
                userId: editingUser.id,
                name: name,
                password: passwordToSend,
                isActive: isActive,
                mustResetPassword: mustReset
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        reloadUsers()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        } else {
            authManager.createUserByAdmin(
                name: name,
                password: password,
                isActive: isActive,
                mustResetPassword: mustReset
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        reloadUsers()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
            }
        }
    }

    private func deleteUser(_ userId: Int) {
        authManager.deleteUser(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    reloadUsers()
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}

private struct AdminUserRow: Identifiable {
    let id: Int
    let name: String
    let is_active: Bool
    let is_admin: Bool
    let must_reset_password: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String else { return nil }
        self.id = id
        self.name = name
        self.is_active = dict["is_active"] as? Bool ?? true
        self.is_admin = dict["is_admin"] as? Bool ?? false
        self.must_reset_password = dict["must_reset_password"] as? Bool ?? false
    }
}

private struct AdminUserEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager

    let existing: AdminUserRow?
    let onSave: (String, String, Bool, Bool) -> Void

    @State private var name = ""
    @State private var password = ""
    @State private var isActive = true
    @State private var mustReset = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя") {
                    TextField("Имя пользователя", text: $name)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section(existing == nil ? "Пароль" : "Новый пароль (опционально)") {
                    SecureField(existing == nil ? "Временный пароль" : "Оставьте пустым, чтобы не менять", text: $password)
                }
                Section("Состояние") {
                    Toggle("Активен", isOn: $isActive)
                    Toggle("Запросить смену пароля", isOn: $mustReset)
                }
            }
            .navigationTitle(existing == nil ? "Новый пользователь" : "Редактирование")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed, password, isActive, mustReset)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    isActive = existing.is_active
                    mustReset = existing.must_reset_password
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if existing == nil {
            return password.count >= 8
        }
        if password.isEmpty { return true }
        return password.count >= 8
    }
}
