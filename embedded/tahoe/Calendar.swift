import SwiftUI

/// Native grid and compact navigation following macos_ui's date-selector
/// pattern. Changes the viewed date, never the system clock or calendar data.
struct TahoeCalendar: View {
    @State private var date = Date()
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @FocusState private var focusedDate: Date?
    @Environment(\.layoutDirection) private var layoutDirection
    private var calendar: Calendar { .current }
    private var weekdays: [String] {
        let labels = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { labels[($0 + calendar.firstWeekday - 1) % 7] }
    }
    private var days: [Date?] {
        guard let count = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var values: [Date?] = Array(repeating: nil, count: leading)
        values += count.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }.map(Optional.some)
        values += Array(repeating: nil, count: (7 - values.count % 7) % 7)
        return values
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(date.formatted(.dateTime.weekday(.wide))).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day().month(.wide))).font(.system(size: 28, weight: .light))
            Divider().opacity(0.4)
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 13, weight: .semibold))
                Spacer()
                TahoeToolbarButton(symbol: "chevron.left", label: "Previous month") { changeMonth(-1) }
                TahoeToolbarButton(symbol: "chevron.right", label: "Next month") { changeMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in Text(weekdays[index]).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(height: 22) }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] { dayButton(day) }
                    else { Color.clear.frame(height: 30).accessibilityHidden(true) }
                }
            }
            HStack {
                Button(TahoeStrings.ui("Open Agenda")) { TahoeWorkspace.shared.openTools("Agenda") }.buttonStyle(TahoeControlStyle())
                Spacer()
                Button(TahoeStrings.ui("Today")) { date = Date(); month = calendar.dateInterval(of: .month, for: date)?.start ?? date }.buttonStyle(TahoeControlStyle())
            }.padding(.top, 4)
        }.tahoeGlassGroup().padding(18).modifier(TahoeGlass(radius: 18)).shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }
    private func dayButton(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: date)
        return Button { date = day; focusedDate = day } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))").font(.system(size: 12, weight: selected ? .semibold : .regular))
                Circle().fill(calendar.isDateInToday(day) ? (selected ? Color.white : TahoeDesign.accent) : .clear).frame(width: 3, height: 3)
            }.frame(maxWidth: .infinity).frame(height: 30)
                .foregroundStyle(selected ? TahoeDesign.accentForeground : .primary)
                .background(selected ? TahoeDesign.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(TahoePressStyle()).accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            .focused($focusedDate, equals: day)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .onKeyPress { event in
                let offset: Int
                switch event.key { case .leftArrow: offset = layoutDirection == .rightToLeft ? 1 : -1; case .rightArrow: offset = layoutDirection == .rightToLeft ? -1 : 1; case .upArrow: offset = -7; case .downArrow: offset = 7; default: return .ignored }
                if let next = calendar.date(byAdding: .day, value: offset, to: date) {
                    date = next; month = calendar.dateInterval(of: .month, for: next)?.start ?? month
                    DispatchQueue.main.async { focusedDate = next }
                }
                return .handled
            }
    }
    private func changeMonth(_ amount: Int) { month = calendar.date(byAdding: .month, value: amount, to: month) ?? month }
}

