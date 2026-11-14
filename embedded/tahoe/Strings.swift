import Foundation

enum TahoeStrings {
    /// A separate table avoids collisions with the pinned runtime's strings.
    /// Dynamic website/file/chat titles never pass through this function.
    static func ui(_ key: String) -> String {
        NSLocalizedString(key, tableName: "SideOS", bundle: .main, value: key, comment: "SideOS desktop interface")
    }
}
