@main struct RefreshSourcePolicyTests {
    static func main() {
        let current = "a3ed60e1d198bcda092b84fccd327c40ff5e9195"
        let old = "fd1681e3b4e75e0c877e21c57624c387ff18ada7"
        precondition(SideOSRefreshSourcePolicy.permits(installed: current, archived: current))
        precondition(SideOSRefreshSourcePolicy.permits(installed: current, archived: current.uppercased()))
        precondition(!SideOSRefreshSourcePolicy.permits(installed: current, archived: old), "An old IPA must not replace the whole desktop through refresh")
        precondition(!SideOSRefreshSourcePolicy.permits(installed: old, archived: current), "Upgrades use Install, not the refresh path")
        for value: String? in [nil, "", "development", String(current.prefix(8)), current + "0", " " + current, String(repeating: "z", count: 40)] {
            precondition(!SideOSRefreshSourcePolicy.permits(installed: current, archived: value))
            precondition(!SideOSRefreshSourcePolicy.permits(installed: value, archived: current))
        }
        print("Self-refresh preserves the installed desktop revision; missing, malformed and different source IPAs are rejected")
    }
}
