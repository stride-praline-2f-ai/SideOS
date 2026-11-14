/// Refresh renews signing for the installed SideOS source. Changing versions is
/// an explicit Install operation; a recently imported old IPA must not replace
/// the running desktop during Refresh All or a background shortcut.
enum SideOSRefreshSourcePolicy {
    static func permits(installed: String?, archived: String?) -> Bool {
        func revision(_ value: String?) -> String? {
            guard let value, value.utf8.count == 40,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
            return value.lowercased()
        }
        guard let installed = revision(installed), let archived = revision(archived) else { return false }
        return installed == archived
    }
}
