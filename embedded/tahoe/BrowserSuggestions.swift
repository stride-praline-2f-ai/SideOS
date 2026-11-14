import SwiftUI

/// Google offers this endpoint to search clients, but it is undocumented.
/// Predictions are optional: a normal search always remains available.
/// No local search history, disk cache or cookies are used for these requests.
@MainActor
final class TahoeGoogleSuggestions: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var predictions: [String] = []
    @Published var selectedRow: Int?

    // Leading-edge request scheduling, not a per-keystroke debounce:
    // a new query does not wait for the user to stop typing.
    private let requestInterval: TimeInterval = 0.11
    private var scheduled: Task<Void, Never>?
    private var requests: [UInt64: Task<Void, Never>] = [:]
    private var nextRequestID: UInt64 = 0
    private var latestAppliedRequestID: UInt64 = 0
    private var lastRequestStart: TimeInterval = -100
    private var lastRawPredictions: [String] = []
    private var isPrivate = false

    private static let network: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 6
        return URLSession(configuration: configuration)
    }()

    /// Protect likely URLs, addresses, credentials and local hostnames.
    /// One character can show the local Search Google action, but only two
    /// or more characters are eligible for remote suggestions.
    static func isSearchInput(_ input: String) -> Bool {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...120).contains(value.count) else { return false }
        return !isLikelyAddress(value)
    }

    private static func isLikelyAddress(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard !value.contains("@"), !value.contains("\\"),
              !value.contains("://"), !lower.hasPrefix("localhost"),
              !lower.hasPrefix("www."), !lower.hasPrefix("file:"),
              !lower.hasPrefix("about:") else { return true }
        if !value.contains(where: { $0.isWhitespace }) &&
            (value.contains(".") || value.contains("/") || value.contains(":")) {
            return true
        }
        return false
    }

    var shouldPresent: Bool {
        !query.isEmpty && query.count <= 120 && !Self.isLikelyAddress(query)
    }

    var selectedSuggestion: String {
        guard let row = selectedRow, predictions.indices.contains(row) else { return query }
        return predictions[row]
    }

    func selectNext(_ increment: Int) {
        let numberOfRows = predictions.count + 1
        let previous = selectedRow ?? (increment > 0 ? -1 : 0)
        selectedRow = (previous + increment + numberOfRows) % numberOfRows
    }

    private func cancelPendingRequests() {
        scheduled?.cancel()
        scheduled = nil
        for task in requests.values { task.cancel() }
        requests.removeAll()
    }

    func dismiss() {
        cancelPendingRequests()
        lastRawPredictions = []
        latestAppliedRequestID = 0
        predictions = []
        selectedRow = nil
        query = ""
        isPrivate = false
    }

    func update(_ input: String, privateBrowsing: Bool) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != value || isPrivate != privateBrowsing else { return }
        let switchedPrivacy = isPrivate != privateBrowsing
        query = value
        isPrivate = privateBrowsing
        selectedRow = nil
        scheduled?.cancel()
        scheduled = nil

        guard Self.isSearchInput(value), !privateBrowsing, TahoePreferences.shared.value.remoteSuggestions ?? true,
              (TahoePreferences.shared.value.searchProvider ?? .google) == .google else {
            // As soon as a private tab or URL is encountered, cancel all
            // network requests and drop any saved predictions from memory.
            cancelPendingRequests()
            lastRawPredictions = []
            predictions = []
            latestAppliedRequestID = 0
            return
        }
        if switchedPrivacy {
            lastRawPredictions = []
            predictions = []
            latestAppliedRequestID = 0
        }

        // Keep relevant results visible while the person continues typing.
        // Never display a prediction that does not match the current input.
        predictions = Self.matching(lastRawPredictions, for: value)

        // Throttle on the leading edge. First eligible input starts now.
        // Later keystrokes coalesce, but continuous typing still triggers
        // requests approximately every 110 ms without a trailing pause.
        let now = ProcessInfo.processInfo.systemUptime
        let remaining = max(0, requestInterval - (now - lastRequestStart))
        let requested = value
        scheduled = Task { @MainActor [weak self] in
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
            guard !Task.isCancelled, let self,
                  !self.isPrivate, self.query == requested else { return }
            self.fetch(requested)
        }
    }

    private static func matching(_ values: [String], for value: String) -> [String] {
        let prefix = value.lowercased()
        return Array(values.filter { $0.lowercased().hasPrefix(prefix) }.prefix(6))
    }

    private func fetch(_ requested: String) {
        lastRequestStart = ProcessInfo.processInfo.systemUptime
        nextRequestID += 1
        let id = nextRequestID

        // At most two in-flight network requests. Allow earlier responses
        // to supply relevant prefix predictions as the user is still typing.
        if requests.count >= 2, let oldest = requests.keys.min() {
            requests.removeValue(forKey: oldest)?.cancel()
        }

        requests[id] = Task { @MainActor [weak self] in
            defer { self?.requests.removeValue(forKey: id) }
            var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
            components.queryItems = [
                URLQueryItem(name: "client", value: "firefox"),
                URLQueryItem(name: "q", value: requested)
            ]
            guard let url = components.url else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await Self.network.data(for: request)
                guard !Task.isCancelled, let self, !self.isPrivate,
                      self.shouldPresent,
                      data.count <= 65_536,
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return }

                let json = try JSONSerialization.jsonObject(with: data)
                guard let array = json as? [Any], array.count > 1,
                      let values = array[1] as? [String] else { return }
                var seen = Set<String>()
                var distinct: [String] = []
                for item in values {
                    let candidate = item.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidate.isEmpty, candidate.count <= 160 else { continue }
                    if seen.insert(candidate.lowercased()).inserted {
                        distinct.append(candidate)
                    }
                    if distinct.count == 6 { break }
                }
                // A response for 'barb' may still be relevant for 'barbi'.
                // However, never overwrite a newer request's predictions
                // or show results for an unrelated query.
                guard self.query.lowercased().hasPrefix(requested.lowercased()),
                      id >= self.latestAppliedRequestID else { return }
                self.latestAppliedRequestID = id
                self.lastRawPredictions = distinct
                self.predictions = Self.matching(distinct, for: self.query)
            } catch {
                // Offline, rate-limited or malformed Google responses never
                // block the immediately available local search action.
            }
        }
    }
}

/// Anchors the panel in desktop coordinates even though the address field lives
/// inside a height-limited toolbar sibling of the full browser content view.
struct TahoeBrowserAddressFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

/// Placed on the full browser window, not inside the small title-bar view.
/// That ensures both tap and pointer hit testing work below the toolbar.
struct TahoeBrowserSuggestionsOverlay: View {
    @ObservedObject var tab: TahoeBrowserTab
    @ObservedObject var model: TahoeGoogleSuggestions

    init(tab: TahoeBrowserTab) {
        self.tab = tab
        self.model = tab.suggestions
    }

    @ViewBuilder var body: some View {
        if tab.suggestionsFocused && model.shouldPresent {
            TahoeBrowserSuggestionsPanel(model: model) { input in
                let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                model.dismiss()
                tab.suggestionsFocused = false
                tab.address = value
                tab.navigate()
            }
        }
    }
}

/// A single, system-rendered Liquid Glass sheet. Suggestion rows are normal
/// controls within that surface, not stacked faux-glass capsules.
struct TahoeBrowserSuggestionsPanel: View {
    @ObservedObject var model: TahoeGoogleSuggestions
    let search: (String) -> Void
    @ObservedObject private var preferences = TahoePreferences.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var clarity: Double {
        TahoeNumeric.value(preferences.value.browserGlass, in: 0...1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !model.predictions.isEmpty {
                Text(TahoeStrings.ui("GOOGLE SUGGESTIONS"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
            ForEach(model.predictions.indices, id: \.self) { index in
                suggestionRow(title: model.predictions[index], symbol: "magnifyingglass",
                              index: index) { search(model.predictions[index]) }
                    .accessibilityIdentifier("browser-suggestion-\(index)")
            }
            if !model.predictions.isEmpty {
                Divider().padding(.horizontal, 9).padding(.vertical, 3)
            }
            suggestionRow(title: "Search \((TahoePreferences.shared.value.searchProvider ?? .google).title) for “\(model.query)”",
                          symbol: "arrow.up.left", index: model.predictions.count) {
                search(model.query)
            }
            .accessibilityIdentifier("browser-suggestion-search")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if reduceTransparency || clarity == 0 {
                shape.fill(TahoeDesign.window)
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(
                    (clarity >= 0.95 ? Glass.clear : Glass.regular)
                        .tint((scheme == .dark ? Color.black : Color.white)
                            .opacity((1 - clarity) * 0.28)),
                    in: shape
                )
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 16, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-suggestions-panel")
    }

    private func suggestionRow(title: String, symbol: String, index: Int,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if model.selectedRow == index {
                    Image(systemName: "return")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .background(model.selectedRow == index ?
                        TahoeDesign.accent.opacity(0.16) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isOver in if isOver { model.selectedRow = index } }
        .accessibilityLabel(title)
    }
}
