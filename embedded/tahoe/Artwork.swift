import SwiftUI

extension TahoeWindowKind {
    var title: String { TahoeStrings.ui(sourceTitle) }
    private var sourceTitle: String {
        switch self {
        case .files: return "Finder"
        case .browser: return "Browser"
        case .applications: return "Applications"
        case .settings: return "System Settings"
        case .notes: return "Notes"
        case .calculator: return "Calculator"
        case .downloads: return "Downloads"
        case .utilities: return "Workspace Tools"
        case .installer: return "SideInstaller"
        case .livecontainer: return "LiveContainer"
        case .guest: return "Native App"
        }
    }
    var symbol: String {
        switch self {
        case .files: return "folder.fill"
        case .browser: return "safari"
        case .applications: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        case .notes: return "note.text"
        case .calculator: return "plus.forwardslash.minus"
        case .downloads: return "arrow.down.circle.fill"
        case .utilities: return "square.grid.3x3.square"
        case .installer: return "arrow.down.app.fill"
        case .livecontainer: return "square.stack.3d.up.fill"
        case .guest: return "app.fill"
        }
    }
}

/// Existing project artwork for four familiar app icons; original vector
/// fallbacks and remaining artwork. Provenance is retained in Notices/.
struct TahoeAppIcon: View {
    var kind: TahoeWindowKind
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23).fill(colors)
            if kind == .livecontainer {
                Image("TahoeLiveContainer", bundle: Bundle(for: TahoeArtworkBundleToken.self)).resizable().scaledToFit()
            } else if let image = artwork {
                Image(uiImage: image).resizable().scaledToFit()
            } else if kind == .files {
                FinderFace().fill(Color.white.opacity(0.8)).padding(size * 0.12)
                FinderSmile().stroke(Color(red: 0.04, green: 0.18, blue: 0.4), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .padding(size * 0.16)
            } else if kind == .browser {
                TahoeCompass(size: size)
            } else if kind == .applications {
                TahoeLaunchpadGlyph(size: size)
            } else if kind == .calculator {
                TahoeCalculatorGlyph(size: size)
            } else if kind == .settings {
                Image(systemName: "gearshape.fill").font(.system(size: size * 0.77, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.58)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.45), radius: size * 0.025, y: size * 0.025)
                Circle().fill(Color(white: 0.27).gradient).frame(width: size * 0.30, height: size * 0.30)
                    .overlay { Circle().strokeBorder(Color(white: 0.72), lineWidth: size * 0.025) }
            } else if kind == .notes {
                RoundedRectangle(cornerRadius: size * 0.14).fill(.white).padding(size * 0.09)
                VStack(spacing: size * 0.07) {
                    Rectangle().fill(.yellow.gradient).frame(height: size * 0.22)
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(.gray.opacity(0.22)).frame(height: max(1, size * 0.025)) }
                    Spacer(minLength: 0)
                }.padding(size * 0.13)
            } else {
                Image(systemName: kind.symbol).font(.system(size: size * 0.61, weight: .medium)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: size * 0.23).strokeBorder(.white.opacity(0.45), lineWidth: 0.7) }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.2), radius: size * 0.06, y: size * 0.04)
        .accessibilityHidden(true)
    }
    private var artwork: UIImage? { TahoeIconArtwork.image(for: kind) }
    private var colors: LinearGradient {
        let pair: [Color]
        switch kind {
        case .files: pair = [.cyan, .blue]
        case .browser: pair = [.white, .gray.opacity(0.3)]
        case .applications: pair = [Color(white: 0.96), Color(white: 0.72)]
        case .settings: pair = [.gray, Color(white: 0.3)]
        case .notes: pair = [.yellow, .orange]
        case .calculator: pair = [Color(white: 0.35), Color(white: 0.15)]
        case .downloads: pair = [.cyan, .teal]
        case .utilities: pair = [.indigo, .purple]
        case .guest, .installer, .livecontainer: pair = [.indigo, .purple]
        }
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private final class TahoeArtworkBundleToken: NSObject { }
private enum TahoeIconArtwork {
    // Asset lookup belongs to the module containing the desktop (a framework
    // in the real host, the application in the simulator preview).
    static func image(for kind: TahoeWindowKind) -> UIImage? {
        if kind == .installer { return BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(false) }
        return nil
    }
}

private struct FinderFace: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.58, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: 0)); p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: r.width * 0.48, y: r.height)); p.addLine(to: CGPoint(x: r.width * 0.52, y: r.height * 0.57))
        p.addLine(to: CGPoint(x: r.width * 0.40, y: r.height * 0.57)); p.closeSubpath()
        return p
    }
}
private struct FinderSmile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for x in [0.25, 0.76] { p.move(to: CGPoint(x: r.width * x, y: r.height * 0.27)); p.addLine(to: CGPoint(x: r.width * x, y: r.height * 0.4)) }
        p.move(to: CGPoint(x: r.width * 0.2, y: r.height * 0.68))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.82, y: r.height * 0.68), control: CGPoint(x: r.width * 0.52, y: r.height * 0.92))
        return p
    }
}

struct TahoeWallpaper: View {
    var style: String?
    @ObservedObject private var preferences = TahoePreferences.shared
    @ObservedObject private var photo = TahoeWallpaperPhoto.shared
    @EnvironmentObject private var workspace: TahoeWorkspace
    var body: some View {
        let selected = style ?? preferences.value.spaceWallpapers?[String(workspace.state.currentSpace)] ?? preferences.value.wallpaper
        let warm = selected == "dawn"
        let graphite = selected == "graphite"
        GeometryReader { geometry in
            ZStack {
                if selected == "custom", let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height, alignment: .center).clipped()
                } else if selected == "coast" || selected == "custom" {
                    Image("TahoeGoldenGate", bundle: Bundle(for: TahoeArtworkBundleToken.self))
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center).clipped()
                } else {
                LinearGradient(colors: graphite ? [Color(white: 0.1), Color(white: 0.28), .black] :
                    warm ? [Color(red: 0.42, green: 0.30, blue: 0.62), Color(red: 0.98, green: 0.65, blue: 0.48), Color(red: 0.55, green: 0.77, blue: 0.83)] :
                    [Color(red: 0.07, green: 0.23, blue: 0.48), Color(red: 0.45, green: 0.73, blue: 0.86), Color(red: 0.10, green: 0.48, blue: 0.62)], startPoint: .top, endPoint: .bottom)
                Circle().fill((warm ? Color.orange : Color.white).opacity(0.5)).frame(width: geometry.size.width * 0.4)
                    .blur(radius: 80).offset(x: geometry.size.width * 0.25, y: -geometry.size.height * 0.26)
                Canvas { context, size in
                    for index in 0..<5 {
                        let t = CGFloat(index)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height * (0.30 + t * 0.1)))
                        path.addCurve(to: CGPoint(x: size.width, y: size.height * (0.42 + t * 0.12)),
                                      control1: CGPoint(x: size.width * 0.20, y: size.height * (0.60 - t * 0.03)),
                                      control2: CGPoint(x: size.width * 0.58, y: size.height * (0.08 + t * 0.13)))
                        path.addLine(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height)); path.closeSubpath()
                        let hue = warm ? 0.59 + Double(index) * 0.015 : 0.58 + Double(index) * 0.012
                        let color = graphite ? Color(white: 0.22 - Double(index) * 0.025) : Color(hue: hue, saturation: 0.62, brightness: 0.65 - Double(index) * 0.075)
                        context.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(0.8), color]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                    }
                    for index in 0..<15 {
                        let y = size.height * (0.72 + CGFloat(index) * 0.018)
                        let line = Path(CGRect(x: size.width * 0.45, y: y, width: size.width * 0.3, height: 0.5))
                        context.fill(line, with: .color(.white.opacity(0.05)))
                    }
                }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Original vector folder artwork with a folded tab, lit front and lower edge.
struct TahoeFolderIcon: View {
    var size: CGFloat = 60
    var body: some View {
        ZStack {
            TahoeFolderBack().fill(LinearGradient(colors: [Color(red: 0.08, green: 0.67, blue: 0.91), Color(red: 0.04, green: 0.46, blue: 0.79)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.065).fill(Color(red: 0.68, green: 0.91, blue: 0.98)).frame(width: size * 0.85, height: size * 0.51).offset(y: -size * 0.015)
            RoundedRectangle(cornerRadius: size * 0.075).fill(LinearGradient(colors: [Color(red: 0.32, green: 0.83, blue: 0.99), Color(red: 0.10, green: 0.66, blue: 0.94)], startPoint: .top, endPoint: .bottom))
                .overlay { RoundedRectangle(cornerRadius: size * 0.075).strokeBorder(.white.opacity(0.32), lineWidth: 0.6) }
                .frame(width: size * 0.94, height: size * 0.61).offset(y: size * 0.10)
        }.frame(width: size, height: size).shadow(color: .black.opacity(0.25), radius: size * 0.035, y: size * 0.04).accessibilityHidden(true)
    }
}
private struct TahoeFolderBack: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.width * 0.03, y: r.height * 0.22))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.10, y: r.height * 0.13), control: CGPoint(x: r.width * 0.03, y: r.height * 0.13))
        p.addLine(to: CGPoint(x: r.width * 0.38, y: r.height * 0.13))
        p.addLine(to: CGPoint(x: r.width * 0.47, y: r.height * 0.22))
        p.addLine(to: CGPoint(x: r.width * 0.91, y: r.height * 0.22))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.97, y: r.height * 0.29), control: CGPoint(x: r.width * 0.97, y: r.height * 0.22))
        p.addLine(to: CGPoint(x: r.width * 0.97, y: r.height * 0.77))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.90, y: r.height * 0.85), control: CGPoint(x: r.width * 0.97, y: r.height * 0.85))
        p.addLine(to: CGPoint(x: r.width * 0.10, y: r.height * 0.85))
        p.addQuadCurve(to: CGPoint(x: r.width * 0.03, y: r.height * 0.77), control: CGPoint(x: r.width * 0.03, y: r.height * 0.85)); p.closeSubpath()
        return p
    }
}

struct TahoeTrashIcon: View {
    var full: Bool
    var size: CGFloat
    var body: some View {
        ZStack {
            if full {
                RoundedRectangle(cornerRadius: 1).fill(.white.gradient).frame(width: size * 0.42, height: size * 0.56).rotationEffect(.degrees(-16)).offset(x: -size * 0.06, y: -size * 0.08)
                RoundedRectangle(cornerRadius: 1).fill(Color(white: 0.85).gradient).frame(width: size * 0.38, height: size * 0.50).rotationEffect(.degrees(18)).offset(x: size * 0.10, y: -size * 0.07)
            }
            Image(systemName: "trash").resizable().scaledToFit().foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.55), .white.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(size * 0.10)
        }.frame(width: size, height: size).shadow(color: .black.opacity(0.25), radius: 2, y: 2).accessibilityHidden(true)
    }
}

private struct TahoeCompass: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(.white.gradient).padding(size * 0.065)
            Circle().fill(LinearGradient(colors: [Color(red: 0.12, green: 0.75, blue: 1), .blue], startPoint: .top, endPoint: .bottom)).padding(size * 0.14)
            ForEach(0..<24, id: \.self) { tick in
                Capsule().fill(.white.opacity(tick % 2 == 0 ? 0.95 : 0.55)).frame(width: max(0.5, size * 0.012), height: size * (tick % 2 == 0 ? 0.06 : 0.03))
                    .offset(y: -size * 0.285).rotationEffect(.degrees(Double(tick) * 15))
            }
            VStack(spacing: 0) {
                TahoeNeedle().fill(Color(red: 1, green: 0.24, blue: 0.29)).frame(width: size * 0.17, height: size * 0.33)
                TahoeNeedle().fill(.white).frame(width: size * 0.17, height: size * 0.33).rotationEffect(.degrees(180))
            }.rotationEffect(.degrees(38)).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        }
    }
}
private struct TahoeNeedle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: r.midX, y: 0)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath(); return p
    }
}
private struct TahoeLaunchpadGlyph: View {
    var size: CGFloat
    private let colors: [Color] = [.pink, .orange, .green, .cyan, .blue, .purple, .red, .mint, .indigo]
    var body: some View {
        VStack(spacing: size * 0.055) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: size * 0.055) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: size * 0.04).fill(colors[row * 3 + column].gradient).frame(width: size * 0.18, height: size * 0.18)
                    }
                }
            }
        }
    }
}
private struct TahoeCalculatorGlyph: View {
    var size: CGFloat
    var body: some View {
        VStack(spacing: size * 0.045) {
            RoundedRectangle(cornerRadius: size * 0.045).fill(Color(white: 0.14)).frame(height: size * 0.21)
                .overlay(alignment: .trailing) { Text(TahoeStrings.ui("0")).font(.system(size: size * 0.17, weight: .light, design: .rounded)).foregroundStyle(.white).padding(.trailing, size * 0.06) }
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: size * 0.045) {
                    ForEach(0..<4, id: \.self) { column in
                        RoundedRectangle(cornerRadius: size * 0.025).fill(column == 3 ? Color.orange : Color(white: 0.59)).frame(height: size * 0.12)
                    }
                }
            }
        }.padding(size * 0.13)
    }
}
