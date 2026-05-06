import SwiftUI

struct TrackerChartCallout: View {
    let title: String
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(rows, id: \.label) { r in
                HStack(spacing: 8) {
                    Text(r.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Text(r.value)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(10)
        .background(FamilyAppStyle.listCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(FamilyAppStyle.cardStroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

