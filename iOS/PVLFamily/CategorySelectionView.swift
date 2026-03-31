import SwiftUI

struct CategorySelectionView: View {
    @Environment(\.dismiss) var dismiss
    let categories: [BudgetView.Category]
    @Binding var selectedId: Int?
    let filterType: String // "income" или "expense"
    let onSelect: () -> Void
    
    // Фильтруем только корневые категории нужного типа
    var filteredRoots: [BudgetView.Category] {
        categories.filter { $0.parent_id == nil && $0.type == filterType }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if filteredRoots.isEmpty {
                    Text("Нет категорий типа '\(filterType == "income" ? "Доход" : "Расход")'")
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    ForEach(filteredRoots) { cat in
                        CategoryNodeView(category: cat, allCategories: categories, filterType: filterType, selectedId: $selectedId, onSelect: {
                            dismiss()
                            onSelect()
                        })
                    }
                }
            }
            .navigationTitle("Выбор категории")
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

struct CategoryNodeView: View {
    let category: BudgetView.Category
    let allCategories: [BudgetView.Category]
    let filterType: String
    @Binding var selectedId: Int?
    let onSelect: () -> Void
    
    // Дети тоже фильтруются по типу
    var children: [BudgetView.Category] {
        allCategories.filter { $0.parent_id == category.id && $0.type == filterType }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                selectedId = category.id
                onSelect()
            }) {
                HStack {
                    Text(category.name)
                        .fontWeight(selectedId == category.id ? .bold : .regular)
                    Spacer()
                    if selectedId == category.id {
                        Image(systemName: "checkmark").foregroundColor(.blue)
                    }
                }
            }
            
            if !children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(children) { child in
                        CategoryNodeView(category: child, allCategories: allCategories, filterType: filterType, selectedId: $selectedId, onSelect: onSelect)
                            .padding(.leading, 20)
                    }
                }
            }
        }
    }
}
