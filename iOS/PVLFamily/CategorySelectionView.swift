import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) var dismiss
    let categories: [BudgetView.Category]
    @Binding var selectedId: Int?
    let filterType: String
    let onSelect: () -> Void
    
    // Фильтруем только корни нужного типа
    var rootCategories: [BudgetView.Category] {
        categories.filter { $0.parent_id == nil && $0.type == filterType }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if rootCategories.isEmpty {
                    Text("Нет категорий типа '\(filterType == "income" ? "Доход" : "Расход")'")
                        .foregroundColor(.gray)
                } else {
                    ForEach(rootCategories) { root in
                        // Корневая категория
                        CategoryChoiceRow(category: root, selectedId: $selectedId, level: 0, onSelect: {
                            dismiss()
                            onSelect()
                        })
                        
                        // Дети
                        let children = categories.filter { $0.parent_id == root.id && $0.type == filterType }
                        ForEach(children) { child in
                            CategoryChoiceRow(category: child, selectedId: $selectedId, level: 1, onSelect: {
                                dismiss()
                                onSelect()
                            })
                        }
                    }
                }
            }
            .navigationTitle("Выберите категорию")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                        onSelect()
                    }
                }
            }
        }
    }
}

struct CategoryChoiceRow: View {
    let category: BudgetView.Category
    @Binding var selectedId: Int?
    let level: Int
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                if level > 0 {
                    Text("↳")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                }
                Text(category.name)
                    .fontWeight(selectedId == category.id ? .bold : .regular)
                    .foregroundColor(.primary)
                Spacer()
                if selectedId == category.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.leading, CGFloat(level * 20))
    }
}
