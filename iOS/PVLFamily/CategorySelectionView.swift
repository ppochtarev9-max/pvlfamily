import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) var dismiss
    let groups: [BudgetView.CategoryGroup]
    @Binding var selectedGroupId: Int?
    @Binding var selectedSubcategoryId: Int?
    let filterType: String
    let onSelect: () -> Void
    
    var filteredGroups: [BudgetView.CategoryGroup] {
        groups.filter { $0.type == filterType && !$0.is_hidden }
    }
    
    var selectedGroup: BudgetView.CategoryGroup? {
        guard let gid = selectedGroupId else { return nil }
        return groups.first { $0.id == gid }
    }
    
    var availableSubs: [BudgetView.SubCategory] {
        guard let group = selectedGroup else { return [] }
        return group.subcategories.filter { !$0.is_hidden }
    }

    var body: some View {
        NavigationStack {
            Form {
                // --- ШАГ 1: ВЫБОР ГРУППЫ ---
                Section("Категория (Группа)") {
                    Menu {
                        ForEach(filteredGroups) { group in
                            Button(action: {
                                selectedGroupId = group.id
                                selectedSubcategoryId = nil // Сброс подкатегории при смене группы
                            }) {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    if selectedGroupId == group.id {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill").foregroundColor(.blue)
                            Text(selectedGroup?.name ?? "Выберите категорию")
                                .foregroundColor(selectedGroup != nil ? .primary : .secondary)
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                        }
                    }
                    
                    // Подсказка, если группа не выбрана
                    if selectedGroup == nil {
                        Text("⚠️ Сначала выберите основную категорию")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // --- ШАГ 2: ВЫБОР ПОДКАТЕГОРИИ (Активен только если выбрана группа) ---
                if selectedGroup != nil {
                    Section("Подкатегория") {
                        if availableSubs.isEmpty {
                            Text("В этой группе нет подкатегорий. Будет использовано значение по умолчанию.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Menu {
                                // Опция "По умолчанию" (если вдруг хотим сбросить, хотя логика требует выбора)
                                // Но лучше требовать выбор из списка, если он есть.
                                
                                ForEach(availableSubs, id: \.id) { sub in
                                    Button(action: {
                                        selectedSubcategoryId = sub.id
                                        dismiss()
                                        onSelect()
                                    }) {
                                        HStack {
                                            Text(sub.name)
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
                                    if let subId = selectedSubcategoryId, let sub = availableSubs.first(where: { $0.id == subId }) {
                                        Text(sub.name)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text("Выберите подкатегорию")
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                                }
                            }
                            
                            // Кнопка подтверждения, если подкатегория выбрана
                            if selectedSubcategoryId != nil {
                                Button("Готово") {
                                    dismiss()
                                    onSelect()
                                }
                                .font(.headline)
                                .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Выбор категории")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}
