import SwiftUI
import SavingsAndGoals
import UI

// MARK: - BillsCalendarView
// The month-grid view of upcoming subscriptions/bills the user asked for:
// dots mark days with expected charges (projected from confirmed
// recurring series); tapping a day lists that day's bills. Reachable from
// Plan → "Bills calendar" (always visible — with an explainer when no
// recurring series are confirmed yet, which is why it felt missing).
struct BillsCalendarView: View {
    @State private var monthOffset = 0
    @State private var selectedDay: Date?
    @State private var bills: [BillsCalendarService.UpcomingBill] = []

    private var calendar: Calendar { Calendar.current }
    private var shownMonth: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(spacing: 12) {
                        header
                        weekdayRow
                        dayGrid
                    }
                }
                selectedDayList
                if bills.isEmpty {
                    GlassCard {
                        Text("No confirmed recurring bills yet. When Mizan spots a repeating charge it appears in Plan"
                            + " as \"Looks recurring — add it?\" — confirming it puts it on this calendar"
                            + " and schedules reminders.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Bills calendar")
        .task { load() }
    }

    private func load() {
        // 120-day horizon covers the shown month ± navigation.
        bills = (try? BillsCalendarService().upcomingBills(withinDays: 120)) ?? []
    }

    private var header: some View {
        HStack {
            Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(monthOffset <= 0)
            Spacer()
            Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }
        }
        .tint(AppTheme.accentMint)
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func billsOn(_ day: Date) -> [BillsCalendarService.UpcomingBill] {
        bills.filter { calendar.isDate($0.nextExpectedDate, inSameDayAs: day) }
    }

    private var dayGrid: some View {
        let interval = calendar.dateInterval(of: .month, for: shownMonth) ?? DateInterval()
        let dayCount = calendar.range(of: .day, in: .month, for: shownMonth)?.count ?? 30
        // Leading blanks so day 1 lands under its weekday.
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 34) }
            ForEach(1...dayCount, id: \.self) { dayNumber in
                let day = calendar.date(byAdding: .day, value: dayNumber - 1, to: interval.start)!
                let hasBills = !billsOn(day).isEmpty
                let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                Button { selectedDay = day } label: {
                    VStack(spacing: 2) {
                        Text("\(dayNumber)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(calendar.isDateInToday(day) ? AppTheme.accentMint : .primary)
                        Circle()
                            .fill(hasBills ? AppTheme.accentCream : .clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? KitTheme.ink.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var selectedDayList: some View {
        if let selectedDay {
            let dayBills = billsOn(selectedDay)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDay.formatted(date: .complete, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                    if dayBills.isEmpty {
                        Text("Nothing expected this day.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(dayBills) { bill in
                            HStack {
                                Text(bill.series.merchantPattern)
                                Spacer()
                                Text("~\(bill.series.expectedAmount) EGP")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
