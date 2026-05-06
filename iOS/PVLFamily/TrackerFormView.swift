import SwiftUI

struct TrackerFormView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    
    let existingLog: TrackerView.BabyLog?
    let onSave: (String, Date, Date?, String) -> Void
    let onDelete: (Int) -> Void
    
    @State private var selectedType: String
    @State private var startTime: Date
    @State private var endTime: Date?
    @State private var isOngoing: Bool
    @State private var note: String
    
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    init(
        isPresented: Binding<Bool>,
        existingLog: TrackerView.BabyLog?,
        onSave: @escaping (String, Date, Date?, String) -> Void,
        onDelete: @escaping (Int) -> Void
    ) {
        self._isPresented = isPresented
        self.existingLog = existingLog
        self.onSave = onSave
        self.onDelete = onDelete
        let s = Self.snapshot(from: existingLog)
        _selectedType = State(initialValue: s.selectedType)
        _startTime = State(initialValue: s.startTime)
        _endTime = State(initialValue: s.endTime)
        _isOngoing = State(initialValue: s.isOngoing)
        _note = State(initialValue: s.note)
    }
    
    private struct FormSnapshot {
        let selectedType: String
        let startTime: Date
        let endTime: Date?
        let isOngoing: Bool
        let note: String
    }
    
    /// Снимок состояния из лога или дефолт для новой записи (`PVLDateParsing` — те же строки API, что в списке).
    private static func snapshot(from log: TrackerView.BabyLog?) -> FormSnapshot {
        guard let log else {
            return FormSnapshot(selectedType: "sleep", startTime: Date(), endTime: nil, isOngoing: true, note: "")
        }
        let noteStr = log.note ?? ""
        let parsedStart = PVLDateParsing.parse(log.start_time)
        
        switch log.event_type {
        case "feed":
            let instant: Date
            if let endStr = log.end_time, let e = PVLDateParsing.parse(endStr) {
                instant = e
            } else if let s = parsedStart {
                instant = s
            } else {
                instant = Date()
            }
            return FormSnapshot(selectedType: log.event_type, startTime: instant, endTime: instant, isOngoing: false, note: noteStr)
            
        default:
            let start = parsedStart ?? Date()
            if let endStr = log.end_time {
                if let end = PVLDateParsing.parse(endStr) {
                    return FormSnapshot(selectedType: log.event_type, startTime: start, endTime: end, isOngoing: false, note: noteStr)
                }
                return FormSnapshot(selectedType: log.event_type, startTime: start, endTime: start, isOngoing: false, note: noteStr)
            }
            return FormSnapshot(selectedType: log.event_type, startTime: start, endTime: nil, isOngoing: true, note: noteStr)
        }
    }
    
    let types: [(id: String, name: String, icon: String)] = [
        ("sleep", "Сон", "moon.fill"),
        ("feed", "Кормление", "drop.fill")
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Тип события") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(types, id: \.id) { type in
                            Button(action: {
                                if selectedType != type.id {
                                    if type.id == "feed" {
                                        isOngoing = false
                                        endTime = Date()
                                    } else {
                                        isOngoing = (existingLog?.end_time == nil)
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
                            .disabled(isSaving || (existingLog != nil))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Section("Время") {
                    DatePicker("Начало", selection: $startTime, displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                    
                    if selectedType == "sleep" {
                        Toggle("Событие еще идет", isOn: $isOngoing)
                            .disabled(isSaving)
                        
                        if !isOngoing {
                            DatePicker("Окончание", selection: Binding(
                                get: { endTime ?? startTime },
                                set: { endTime = $0; isOngoing = false }
                            ), displayedComponents: [.date, .hourAndMinute])
                            .disabled(isSaving)
                        }
                    } else {
                        DatePicker("Время", selection: Binding(
                            get: { startTime },
                            set: { startTime = $0; endTime = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .disabled(isSaving)
                        Text("Кормление считается мгновенным событием")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Заметка") {
                    TextField("Например: плохо засыпал", text: $note)
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
            .onAppear { applySnapshot(from: existingLog) }
            .onChange(of: existingLog?.id) { _, _ in applySnapshot(from: existingLog) }
        }
    }
    
    var formTitle: String {
        if existingLog != nil {
            return selectedType == "sleep" ? "Редактирование сна" : "Редактирование кормления"
        } else {
            return selectedType == "sleep" ? "Новый сон" : "Новое кормление"
        }
    }
    
    private func applySnapshot(from log: TrackerView.BabyLog?) {
        let s = Self.snapshot(from: log)
        selectedType = s.selectedType
        startTime = s.startTime
        endTime = s.endTime
        isOngoing = s.isOngoing
        note = s.note
    }
    
    func submit() {
        guard authManager.token != nil else {
            errorMessage = "Пользователь не авторизован"
            showErrorAlert = true
            return
        }
        
        isSaving = true
        
        var finalEndTime: Date? = nil
        
        if selectedType == "feed" {
            finalEndTime = startTime
        } else {
            if !isOngoing {
                finalEndTime = endTime ?? Date()
                if finalEndTime! < startTime {
                    errorMessage = "Время окончания не может быть раньше начала"
                    showErrorAlert = true
                    isSaving = false
                    return
                }
            }
        }
        
        onSave(selectedType, startTime, finalEndTime, note)
    }
}
