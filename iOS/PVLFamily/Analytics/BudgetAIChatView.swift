import SwiftUI

/// Чат с ИИ по бюджету (server-built safe_payload на backend).
struct BudgetAIChatView: View {
    @EnvironmentObject var authManager: AuthManager

    let selectedUserId: Int?

    @State private var anchorMonth: Date
    @State private var inputText: String = ""
    @State private var isSending: Bool = false
    @State private var errorText: String?
    @State private var messages: [ChatMessage] = []

    init(selectedUserId: Int?, anchorMonth: Date) {
        self.selectedUserId = selectedUserId
        _anchorMonth = State(initialValue: anchorMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().opacity(0.4)

            chatBody

            Divider().opacity(0.4)

            composer
        }
        .background(FamilyAppStyle.screenBackground)
        .navigationTitle("ИИ по бюджету")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if messages.isEmpty {
                messages = [
                    .assistant("Спроси про расходы/доходы/категории за выбранный месяц или за последние 12 месяцев. Я отвечу на основе агрегатов (без выгрузки транзакций).")
                ]
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isSending)

            VStack(spacing: 2) {
                Text("Период")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(monthLabel(anchorMonth))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FamilyAppStyle.screenBackground)
    }

    private var chatBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if let err = errorText {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Button(chip) {
                            inputText = chip
                            send(question: chip)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .disabled(isSending)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Напиши вопрос…", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isSending)

                Button {
                    send(question: inputText)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(FamilyAppStyle.screenBackground)
    }

    private var chips: [String] {
        [
            "Сколько денег ушло на квартиру за последние 12 месяцев?",
            "Насколько выросли расходы на квартиру за последние 12 месяцев?",
            "Какие 3 категории сильнее всего выросли по расходам за последние 12 месяцев?",
            "Как меняется доход год к году?",
            "Какие самые крупные операции за последние 12 месяцев и почему?"
        ]
    }

    private func send(question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if isSending { return }
        isSending = true
        errorText = nil

        messages.append(.user(q))
        inputText = ""

        let anchor = String(format: "%04d-%02d",
                            Calendar.current.component(.year, from: anchorMonth),
                            Calendar.current.component(.month, from: anchorMonth))

        let payload = InsightPayload(
            report_type: "budget",
            period: "anchor_month",
            metrics: [:],
            trend_flags: [],
            anomalies: [],
            series: nil,
            breakdowns: nil,
            comparisons: nil,
            notes: "server_build"
        )

        authManager.getInsight(
            kind: "budget",
            payload: payload,
            provider: nil,
            question: q,
            anchorMonth: anchor,
            windowMonths: 72,
            userId: selectedUserId
        ) { result in
            DispatchQueue.main.async {
                isSending = false
                switch result {
                case .success(let r):
                    messages.append(.assistant(renderResponse(r)))
                case .failure(let e):
                    errorText = e.localizedDescription
                    messages.append(.assistant("Не получилось получить ответ. Попробуй ещё раз или укажи вопрос проще."))
                }
            }
        }
    }

    private func renderResponse(_ r: InsightResponse) -> String {
        // Единый “нормальный” текст вместо странной разбивки в UI.
        // LLM уже может отвечать на question; summary_today/summary_month используем как 2 абзаца.
        var parts: [String] = []
        if !r.summary_today.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(r.summary_today.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !r.summary_month.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(r.summary_month.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !r.bullets.isEmpty {
            let bullets = r.bullets.map { "• \($0)" }.joined(separator: "\n")
            parts.append(bullets)
        }
        if !r.provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Источник: \(r.provider)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func shiftMonth(_ delta: Int) {
        let cal = Calendar.current
        anchorMonth = cal.date(byAdding: .month, value: delta, to: monthStart(anchorMonth)) ?? anchorMonth
    }

    private func monthStart(_ d: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: d)
        return cal.date(from: comps) ?? d
    }

    private func monthLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }
}
