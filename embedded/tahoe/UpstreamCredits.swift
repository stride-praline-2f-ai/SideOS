import SwiftUI

/// Shared visible attribution in About and Help, in addition to full licences.
struct TahoeUpstreamCredits: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Built with these projects").font(.headline)
            Link("SideInstaller by FrizzleM", destination: URL(string: "https://github.com/FrizzleM/SideInstaller")!)
                .font(.system(size: 15, weight: .semibold))
            Link("LiveContainer by the LiveContainer contributors", destination: URL(string: "https://github.com/LiveContainer/LiveContainer")!)
                .font(.callout.weight(.medium))
            Link("StikJIT by the StikDebug contributors", destination: URL(string: "https://github.com/StikDebug/StikJIT")!)
                .font(.callout.weight(.medium))
            Text("Original authors retain their copyrights. SideOS provides the desktop and integration changes.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("upstream-project-credits")
    }
}
