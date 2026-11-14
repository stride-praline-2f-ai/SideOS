import Foundation

struct TahoeWebLink: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var url: URL
    var symbol: String = "globe"
    var iconData: Data?
    var customIcon: Bool?
    var iconZoom: Double?
    var iconOffsetX: Double?
    var iconOffsetY: Double?
    var folder: String?
}

struct TahoeSavedTab: Codable, Sendable {
    var id: UUID
    var url: URL
    var profile: String
    var zoom: Double
    var identity: String
    var pinned: Bool
    var chatWorkspace: TahoeSavedChatWorkspace?
    var group: String?
}

struct TahoeSavedBrowser: Codable, Sendable {
    let windowID: UUID
    let addresses: [URL]
    let selected: Int
    var chatWorkspaces: [TahoeSavedChatWorkspace?]? = nil
    var tabs: [TahoeSavedTab]? = nil
    var profile: String? = nil
    var selectedTabID: UUID? = nil
    var selectedGroup: String? = nil
    mutating func regenerateTabIDs() {
        let selected = selectedTabID
        var ids: [UUID: UUID] = [:]
        tabs = tabs?.map { tab in var tab = tab; let next = UUID(); ids[tab.id] = next; tab.id = next; return tab }
        selectedTabID = selected.flatMap { ids[$0] }
        if selectedTabID == nil, let tabs, tabs.indices.contains(self.selected) { selectedTabID = tabs[self.selected].id }
    }
}

struct TahoeSavedWorkspace: Codable, Sendable {
    var version = 1
    var windows: [TahoeWindow]
    var browsers: [TahoeSavedBrowser]
    var active: UUID?
    var space: Int
    var spaces: Int
    var tileFraction: Double?
}

enum TahoeStorage {
    static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TahoeDesktop", isDirectory: true)
    }
    static func read<T: Decodable>(_ name: String, as type: T.Type) throws -> T? {
        let file = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: file)) }
        catch {
            let backup = root.appendingPathComponent(name + ".previous")
            guard let data = try? Data(contentsOf: backup), let recovered = try? JSONDecoder().decode(type, from: data) else { throw error }
            UserDefaults.standard.set(name, forKey: "TahoeRecoveredFile")
            return recovered
        }
    }
    static func write<T: Codable>(_ value: T, to name: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let destination = root.appendingPathComponent(name)
        // A parsable JSON object can still have the wrong schema. Never replace
        // a recoverable backup with a primary this model cannot decode.
        if let previous = try? Data(contentsOf: destination),
           (try? JSONDecoder().decode(T.self, from: previous)) != nil {
            try previous.write(to: root.appendingPathComponent(name + ".previous"), options: .atomic)
        }
        try encoder.encode(value).write(to: destination, options: .atomic)
    }
    static func isWebURL(_ url: URL) -> Bool { ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil }
}

actor TahoeStorageWriter {
    static let shared = TahoeStorageWriter()
    private var revisions: [String: UInt64] = [:]
    func write<T: Codable & Sendable>(_ snapshot: T, to name: String, revision: UInt64) throws {
        guard revision >= revisions[name, default: 0] else { return }
        try TahoeStorage.write(snapshot, to: name)
        revisions[name] = revision
    }
}

/// No expression evaluation: the calculator only accepts its fixed operations.
struct TahoeCalculator {
    private(set) var display = "0"
    private var accumulator: Double?
    private var operation: String?
    private var replaceEntry = true
    mutating func press(_ key: String) {
        if key == "AC" { self = TahoeCalculator(); return }
        if key == "+/−" { if let value = Double(display) { display = format(-value) }; return }
        if key == "%" { if let value = Double(display) { display = format(value / 100) }; return }
        if ["+", "−", "×", "÷", "="].contains(key) {
            let value = Double(display) ?? 0
            if let lhs = accumulator, let operation, !replaceEntry {
                let result: Double
                switch operation { case "+": result = lhs + value; case "−": result = lhs - value; case "×": result = lhs * value; default: result = lhs / value }
                display = result.isFinite ? format(result) : "Error"
                accumulator = result.isFinite ? result : nil
            } else { accumulator = value }
            operation = key == "=" ? nil : key
            if key == "=" { accumulator = nil }
            replaceEntry = true
            return
        }
        guard key == "." || (key.count == 1 && key.first!.isNumber) else { return }
        if replaceEntry || display == "Error" { display = key == "." ? "0." : key; replaceEntry = false }
        else if key == "." { if !display.contains(".") { display += "." } }
        else if display.count < 15 { display = display == "0" ? key : display + key }
    }
    private func format(_ number: Double) -> String { String(format: "%.12g", number) }
}
