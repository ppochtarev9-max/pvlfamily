import SwiftUI

struct TrackerFormView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    
    // Входные данные
    let existingLog: TrackerView.BabyLog?
    let onSave: (String, Date, Date?, String) -> Void
    let onDelete: (Int) -> Void
    
    // Состояния данных
    @State private var selectedType: String = "sleep"
    @State private var startTime: Date = Date()
    @State private var endTime: Date? = nil
    @State private var isOngoing: Bool = true
    @State private var note: String = ""
    
    // Состояния UI
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    // Доступные типы событий
    let types: [(id: String, name: String, icon: String)] = [
        ("sleep", "Сон", "moon.fill"),
        ("feed", "Кормление", "drop.fill")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                // 1. Выбор типа события
                Section("Тип события") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(types, id: \.id) { type in
                            Button(action: {
                                // Если меняем тип, сбрасываем логику "идет/не идет" для нового типа
                                if selectedType != type.id {
                                    if type.id == "feed" {
                                        isOngoing = false // Кормление всегда завершено
                                        endTime = Date()
                                    } else {
                                        isOngoing = (existingLog?.end_time == nil) // Для сна смотрим исходное состояние
                                    }
                                }
                                selectedType = type.id
                            }) {
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
                                .background(selectedType == type.id ? FamilyAppStyle.accent : Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isSaving || (existingLog != nil)) // Нельзя менять тип при редактировании существующего
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // 2. Настройки времени
                Section("Время") {
                    DatePicker("Начало", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                    
                    // Показываем тумблер ТОЛЬКО для сна
                    if selectedType == "sleep" {
                        Toggle("Событие еще идет", isOn: $isOngoing)
                            .disabled(isSaving)
                        
                        if !isOngoing {
                            DatePicker("Окончание", selection: Binding(
                                get: { endTime ?? Date() },
                                set: { endTime = $0; isOngoing = false }
                            ), displayedComponents: [.date, .hourAndMinute])
                            .disabled(isSaving)
                        }
                    } else {
                        // Для кормлений всегда показываем время окончания (оно же начало)
                        DatePicker("Время", selection: Binding(
                            get: { startTime }, // Для простоты кормление = старт
                            set: { startTime = $0; endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                        Text("Кормление считается мгновенным событием")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 3. Заметка
                Section("Заметка") {
                    TextField("Например: плохо засыпал", text: $note)
                        .disabled(isSaving)
                }
                
                // 4. Удаление (только для существующих)
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
                
                // 5. Кнопка сохранения
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
            .pvlFormScreenStyle()
            .tint(FamilyAppStyle.accent)
            .navigationTitle(formTitle)
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
                loadDataFromLog()
            }
        }
    }
    
    // --- ЛОГИКА ---
    
    var formTitle: String {
        if let log = existingLog {
            return selectedType == "sleep" ? "Редактирование сна" : "Редактирование кормления"
        } else {
            return selectedType == "sleep" ? "Новый сон" : "Новое кормление"
        }
    }
    
    func loadDataFromLog() {
        guard let log = existingLog else {
            // Новый элемент: сброс по умолчанию
            selectedType = "sleep"
            startTime = Date()
            endTime = nil
            isOngoing = true
            note = ""
            return
        }
        
        // Загрузка существующего
        selectedType = log.event_type
        note = log.note ?? ""
        
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Парсим время начала
        if let start = iso.date(from: log.start_time) {
            startTime = start
        } else {
            // Пробуем без миллисекунд, если формат другой
            iso.formatOptions = [.withInternetDateTime]
            if let start = iso.date(from: log.start_time) {
                startTime = start
            }
        }
        
        // ПАРСИМ ВРЕМЯ ОКОНЧАНИЯ И СТАВИМ ФЛАГ
        if let endStr = log.end_time {
            // Есть время окончания -> событие ЗАВЕРШЕНО
            var endDate: Date? = nil
            if let end = iso.date(from: endStr) {
                endDate = end
            } else {
                iso.formatOptions = [.withInternetDateTime]
                endDate = iso.date(from: endStr)
            }
            
            endTime = endDate ?? Date()
            isOngoing = false // <-- ГЛАВНОЕ ИСПРАВЛЕНИЕ: явно выключаем
        } else {
            // Нет времени окончания -> событие ИДЕТ
            endTime = nil
            isOngoing = true
        }
        
        // Защита: если это кормление, оно не может быть "ongoing" в нашем понимании длинного процесса
        if selectedType == "feed" {
            isOngoing = false
        }
    }
    
    func submit() {
        guard authManager.token != nil else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        // Определяем финальное время окончания
        var finalEndTime: Date? = nil
        
        if selectedType == "feed" {
            // Кормление всегда мгновенное
            finalEndTime = startTime
        } else {
            // Сон
            if !isOngoing {
                finalEndTime = endTime ?? Date()
                // Проверка: конец не раньше начала
                if finalEndTime! < startTime {
                    errorMessage = "Время окончания не может быть раньше начала"
                    showErrorAlert = true
                    isSaving = false
                    return
                }
            }
            // Если isOngoing == true, finalEndTime останется nil
        }
        
        onSave(selectedType, startTime, finalEndTime, note)
    }
}
