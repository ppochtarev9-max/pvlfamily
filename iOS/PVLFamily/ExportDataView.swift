import SwiftUI
import UniformTypeIdentifiers

struct ExportDataView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    // Настройки экспорта
    @State private var exportType: String = "budget" // "budget" или "sleep"
    @State private var periodType: String = "week"   // "week", "month", "year", "all"
    
    // Состояния процесса
    @State private var isExporting = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @State private var exportedFileURL: URL?
    
    var body: some View {
        Form {
            // Выбор типа данных
            Section("Что выгружаем?") {
                Picker("Тип данных", selection: $exportType) {
                    Text("Бюджет (Транзакции)").tag("budget")
                    Text("Трекер сна").tag("sleep")
                }
                .pickerStyle(.segmented)
            }
            
            // Выбор периода
            Section("Период") {
                Picker("Период", selection: $periodType) {
                    Text("Неделя").tag("week")
                    Text("Месяц").tag("month")
                    Text("Год").tag("year")
                    Text("Все время").tag("all")
                }
            }
            
            // Кнопка действия
            Section {
                Button(action: startExport) {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Подготовка...")
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "doc.badge.arrow.down")
                            Text("Выгрузить в Excel")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .disabled(isExporting)
            } footer: {
                Text("Файл будет сформирован и открыт в меню «Поделиться» для сохранения или отправки.")
            }
        }
        .pvlFormScreenStyle()
        .tint(FamilyAppStyle.accent)
        .navigationTitle("Экспорт данных")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ошибка", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }
    
    func startExport() {
        guard let token = authManager.token else {
            errorMessage = "Требуется авторизация"
            showErrorAlert = true
            return
        }
        
        isExporting = true
        
        // Расчет дат
        let calendar = Calendar.current
        let now = Date()
        var startDate: Date
        
        switch periodType {
        case "week":
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case "month":
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case "year":
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        default: // "all" - берем далекое прошлое
            startDate = calendar.date(byAdding: .year, value: -10, to: now) ?? now
        }
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let startStr = isoFormatter.string(from: startDate)
        let endStr = isoFormatter.string(from: now)
        
        // Формирование URL
        let endpoint = exportType == "budget" ? "/budget/export/excel" : "/tracker/export/excel"
        let urlString = "\(authManager.baseURL)\(endpoint)?start_date=\(startStr)&end_date=\(endStr)"
        
        guard let url = URL(string: urlString) else {
            finishExport(success: false, error: "Ошибка формирования URL")
            return
        }
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isExporting = false
                
                if let error = error {
                    finishExport(success: false, error: "Ошибка сети: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    finishExport(success: false, error: "Ошибка сервера. Проверьте права доступа.")
                    return
                }
                
                guard let data = data else {
                    finishExport(success: false, error: "Пустой ответ от сервера")
                    return
                }
                
                // Сохранение во временный файл
                let tempDir = FileManager.default.temporaryDirectory
                let fileName = "\(exportType)_export_\(Date().timeIntervalSince1970).xlsx"
                let fileURL = tempDir.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    self.exportedFileURL = fileURL
                    self.showingShareSheet = true
                } catch {
                    finishExport(success: false, error: "Не удалось сохранить файл: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    func finishExport(success: Bool, error: String?) {
        if !success {
            self.errorMessage = error
            self.showErrorAlert = true
        }
    }
}

// Обертка для шеринга
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
