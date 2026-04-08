import SwiftUI

struct TrackerFormView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    let existingLog: TrackerView.BabyLog?
    let onSave: (String, Date, Date?, String) -> Void
    let onDelete: (Int) -> Void
    
    // Данные
    @State private var selectedType: String = "sleep"
    @State private var startTime: Date = Date()
    @State private var endTime: Date? = nil
    @State private var isOngoing: Bool = true
    @State private var note: String = ""
    
    // Состояния UI
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    let types: [(id: String, name: String, icon: String)] = [
        ("sleep", "Сон", "moon.fill"),
        ("feed", "Кормление", "fork.knife"),
        ("diaper", "Памперс", "drop.triangle.fill"),
        ("play", "Игра", "star.fill")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Тип события") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(types, id: \.id) { type in
                            Button(action: { selectedType = type.id }) {
                                VStack(spacing: 6) {
                                    Image(systemName: type.icon)
                                        .font(.title2)
                                        .foregroundColor(selectedType == type.id ? .white : .primary)
                                    
                                    Text(type.name)
                                        .font(.caption)
                                        .foregroundColor(selectedType == type.id ? .white : .primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedType == type.id ? Color.blue : Color(.systemGray5))
                                .cornerRadius(12)
                            }
                            .disabled(isSaving)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Section("Время") {
                    DatePicker("Начало", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                    
                    Toggle("Событие еще идет", isOn: $isOngoing)
                        .disabled(isSaving)
                    
                    if !isOngoing {
                        DatePicker("Окончание", selection: Binding(
                            get: { endTime ?? Date() },
                            set: { endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                    }
                }
                
                Section("Заметка") {
                    TextField("Например: хорошо покушал", text: $note)
                        .disabled(isSaving)
                }
                
                if let log = existingLog {
                    Section {
                        Button(role: .destructive, action: {
                            onDelete(log.id)
                        }) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Удалить запись")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                
                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSaving ? "Сохранение..." : (existingLog != nil ? "Сохранить" : "Добавить"))
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle(existingLog != nil ? "Редактирование" : "Новое событие")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { isPresented = false }
                        .disabled(isSaving)
                }
            }
            .alert("Ошибка", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
            .onAppear {
                if let log = existingLog {
                    selectedType = log.event_type
                    let iso = ISO8601DateFormatter()
                    if let start = iso.date(from: log.start_time) {
                        startTime = start
                    }
                    if let end = log.end_time, let endDate = iso.date(from: end) {
                        endTime = endDate
                        isOngoing = false
                    } else {
                        isOngoing = true
                    }
                    note = log.note ?? ""
                }
            }
        }
    }
    
    func submit() {
        guard let token = authManager.token else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        let finalEndTime = isOngoing ? nil : endTime
        onSave(selectedType, startTime, finalEndTime, note)
    }
    
    func setSaving(_ saving: Bool) {
        self.isSaving = saving
    }
}
