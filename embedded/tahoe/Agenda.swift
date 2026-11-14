import SwiftUI
import EventKit

struct TahoeAgendaItem: Identifiable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendar: String
    var allDay: Bool
}
actor TahoeAgendaWorker {
    static let shared = TahoeAgendaWorker()
    private let store = EKEventStore()
    func load(requestAccess: Bool) async throws -> [TahoeAgendaItem] {
        if requestAccess, EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            guard try await store.requestFullAccessToEvents() else { throw CocoaError(.userCancelled) }
        }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw NSError(domain: "SideOS.Calendar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar access is off. You can enable it in iPad Settings. The desktop date picker works without calendar access."])
        }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }.map {
            TahoeAgendaItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate,
                end: $0.endDate, calendar: $0.calendar.title, allDay: $0.isAllDay)
        }
    }
}
struct TahoeAgenda: View {
    @State private var events: [TahoeAgendaItem] = []
    @State private var message: String?
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(TahoeStrings.ui("Next Seven Days")).font(.title3.bold()); Spacer(); Button(TahoeStrings.ui("Refresh")) { load(requestAccess: false) } }
            Text(TahoeStrings.ui("Calendar events are read from this iPad for this view. They are not added to workspace files or diagnostics.")).font(.caption).foregroundStyle(.secondary)
            if loading { ProgressView() }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                Button(TahoeStrings.ui("Connect Calendar")) { load(requestAccess: true) }.buttonStyle(TahoeControlStyle())
            } else if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
                Button(TahoeStrings.ui("Open iPad Settings")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(TahoeControlStyle())
            }
            List(events) { event in
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title).fontWeight(.medium)
                    Text(event.allDay ? event.start.formatted(date: .abbreviated, time: .omitted) + " · All day" : event.start.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                    Text(event.calendar).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.listStyle(.plain)
        }.padding(20).task { if EKEventStore.authorizationStatus(for: .event) == .fullAccess { load(requestAccess: false) } }
    }
    private func load(requestAccess: Bool) {
        guard !loading else { return }; loading = true; message = nil
        Task { defer { loading = false }; do { events = try await TahoeAgendaWorker.shared.load(requestAccess: requestAccess); if events.isEmpty { message = "No events in the next seven days." } } catch { events = []; message = error.localizedDescription } }
    }
}
