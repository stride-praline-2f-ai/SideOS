import SwiftUI

// Native adaptations of macos-components' field/slider/radio/feedback families
// and MacVue's matching size tokens, selection pill and repeat behaviour.
// Flutter macos_ui contributes toolbar overflow and focus/layout patterns.
typealias TahoeControlSize = TahoeControlStyle.Size

extension TahoeControlStyle.Size {
    var fontSize: CGFloat { self == .mini ? 10 : self == .small ? 11 : 13 }
    var fieldRadius: CGFloat { switch self { case .mini: return 4; case .small: return 5; case .regular: return 6; case .large: return 7; case .extraLarge: return 9 } }
    var thumbSize: CGSize {
        switch self {
        case .mini: return CGSize(width: 16, height: 12)
        case .small: return CGSize(width: 18, height: 14)
        case .regular: return CGSize(width: 20, height: 16)
        default: return CGSize(width: 24, height: 20)
        }
    }
    var choiceSize: CGFloat { self == .mini ? 12 : self == .small ? 14 : self == .regular ? 16 : 18 }
    var stepperWidth: CGFloat { switch self { case .mini: return 13; case .small: return 17; case .regular: return 20; case .large: return 23; case .extraLarge: return 30 } }
    var switchWidth: CGFloat { switch self { case .mini: return 36; case .small: return 44; case .regular: return 54; case .large: return 64; case .extraLarge: return 80 } }
    var switchThumb: CGSize {
        switch self { case .mini: return CGSize(width: 21, height: 13); case .small: return CGSize(width: 26, height: 16); case .regular: return CGSize(width: 32, height: 20); case .large: return CGSize(width: 38, height: 24); case .extraLarge: return CGSize(width: 47, height: 30) }
    }
}

private struct TahoeFieldChrome: ViewModifier {
    var focused: Bool
    var size: TahoeControlSize
    var search: Bool
    var invalid: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.font(.system(size: size.fontSize)).padding(.horizontal, 8).frame(minHeight: size.height)
            .background(TahoeDesign.content, in: RoundedRectangle(cornerRadius: search ? 100 : size.fieldRadius))
            .overlay { RoundedRectangle(cornerRadius: search ? 100 : size.fieldRadius).strokeBorder(invalid ? Color.red : Color.primary.opacity(0.18), lineWidth: 0.75) }
            .overlay { RoundedRectangle(cornerRadius: search ? 100 : size.fieldRadius).stroke(focused ? (invalid ? Color.red : TahoeDesign.accent).opacity(0.35) : .clear, lineWidth: 3).padding(-1.5) }
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
    }
}

extension View {
    func tahoeField(focused: Bool = false, size: TahoeControlSize = .regular, search: Bool = false, invalid: Bool = false) -> some View {
        modifier(TahoeFieldChrome(focused: focused, size: size, search: search, invalid: invalid))
    }
}

struct TahoeSearchField: View {
    var title = "Search"
    @Binding var text: String
    var active = true
    var size: TahoeControlSize = .regular
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(title, text: $text).textFieldStyle(.plain).focused($focused).autocorrectionDisabled()
                .onKeyPress(.escape) { if !text.isEmpty { text = "" } else { focused = false }; return .handled }
            if !text.isEmpty {
                Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(TahoePressStyle()).accessibilityLabel("Clear search")
            }
        }.tahoeField(focused: focused, size: size, search: true)
            .onChange(of: active) { _, active in if !active { focused = false } }
    }
}

struct TahoeSlider: View {
    @GestureState private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var step: Double = 0
    var size: TahoeControlSize = .regular
    var ticks = false
    var tinted = true
    var label: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.layoutDirection) private var direction
    @FocusState private var focused: Bool
    private var increment: Double { step > 0 ? step : max(0.001, (range.upperBound - range.lowerBound) / 100) }
    private var fraction: CGFloat { CGFloat(TahoeNumeric.fraction(value, in: range)) }
    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geometry in
                let thumb = size.thumbSize
                let travel = max(0, geometry.size.width - thumb.width)
                let position = thumb.width / 2 + travel * (direction == .rightToLeft ? 1 - fraction : fraction)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12)).frame(height: size == .mini || size == .small ? 4 : 6)
                    if tinted { Capsule().fill(TahoeDesign.accent).frame(width: geometry.size.width * fraction, height: size == .mini || size == .small ? 4 : 6).frame(maxWidth: .infinity, alignment: direction == .rightToLeft ? .trailing : .leading) }
                    Capsule().fill(scheme == .dark ? Color(white: 222 / 255) : .white).frame(width: thumb.width, height: thumb.height)
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                        .overlay { Capsule().stroke(focused ? TahoeDesign.accent.opacity(0.4) : .clear, lineWidth: 3).padding(-2) }
                        .scaleEffect(dragging && !reduceMotion ? 1.12 : 1)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.8), value: dragging)
                        .position(x: position, y: geometry.size.height / 2)
                }.frame(height: geometry.size.height).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, state, _ in state = enabled }.onChanged { event in
                        guard enabled, travel > 0 else { return }
                        focused = true
                        var ratio = Double((event.location.x - thumb.width / 2) / travel)
                        if direction == .rightToLeft { ratio = 1 - ratio }
                        commit(range.lowerBound + ratio * (range.upperBound - range.lowerBound))
                    })
            }.frame(height: max(44, size.height))
            if ticks {
                HStack {
                    Text(range.lowerBound, format: .number); Spacer(); Text((range.lowerBound + range.upperBound) / 2, format: .number); Spacer(); Text(range.upperBound, format: .number)
                }.font(.system(size: 10)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }.opacity(enabled ? 1 : 0.5).focusable(enabled).focused($focused).focusEffectDisabled()
            .onKeyPress { event in
                guard enabled else { return .ignored }
                let amount = increment * (event.modifiers.contains(.shift) ? 10 : 1)
                switch event.key {
                case .leftArrow: commit(value + (direction == .rightToLeft ? amount : -amount))
                case .downArrow: commit(value - amount)
                case .rightArrow: commit(value + (direction == .rightToLeft ? -amount : amount))
                case .upArrow: commit(value + amount)
                case .home: commit(range.lowerBound)
                case .end: commit(range.upperBound)
                default: return .ignored
                }
                return .handled
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...2))))
            .accessibilityAdjustableAction { change in
                switch change { case .increment: commit(value + increment); case .decrement: commit(value - increment); @unknown default: break }
            }
    }
    private func commit(_ next: Double) { if enabled { value = TahoeNumeric.value(next, in: range, step: step) } }
}

struct TahoeChoice: Identifiable {
    var id: String
    var title: String
    var symbol = ""
    var enabled = true
}

struct TahoeSegments: View {
    let options: [TahoeChoice]
    @Binding var selected: Set<String>
    var multiple = false
    var size: TahoeControlSize = .regular
    var label: String
    @Environment(\.colorScheme) private var scheme
    @Namespace private var pill
    @Environment(\.layoutDirection) private var direction
    @FocusState private var focus: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    init(options: [TahoeChoice], selection: Binding<String>, size: TahoeControlSize = .regular, label: String) {
        self.options = options; self.size = size; self.label = label
        _selected = Binding(get: { [selection.wrappedValue] }, set: { if let value = $0.first { selection.wrappedValue = value } })
    }
    init(options: [TahoeChoice], selection: Binding<Set<String>>, size: TahoeControlSize = .regular, label: String) {
        self.options = options; self.size = size; self.label = label; multiple = true; _selected = selection
    }
    var body: some View {
        HStack(spacing: 1) {
            ForEach(options) { option in
                Button { select(option.id) } label: {
                    HStack(spacing: 5) {
                        if !option.symbol.isEmpty { Image(systemName: option.symbol) }
                        if !option.title.isEmpty { Text(option.title) }
                    }.font(.system(size: size.fontSize, weight: .medium)).padding(.horizontal, size == .mini ? 7 : 11)
                        .frame(maxWidth: .infinity).frame(height: size.height - 4)
                        .background {
                            if selected.contains(option.id) {
                                RoundedRectangle(cornerRadius: size.radius).fill(scheme == .dark ? Color.white.opacity(0.18) : .white)
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: multiple ? option.id : "selection", in: pill)
                            }
                        }
                }.buttonStyle(TahoePressStyle()).disabled(!option.enabled).focused($focus, equals: option.id)
                    .accessibilityLabel(option.title.isEmpty ? option.id : option.title)
                    .accessibilityAddTraits(selected.contains(option.id) ? [.isSelected] : [])
                    .onKeyPress { event in
                        let delta: Int
                        switch event.key { case .leftArrow: delta = direction == .rightToLeft ? 1 : -1; case .rightArrow: delta = direction == .rightToLeft ? -1 : 1; default: return .ignored }
                        let index = options.firstIndex(where: { $0.id == option.id })
                        if let next = TahoeMenuNavigation.next(from: index, direction: delta, enabled: options.map(\.enabled)) {
                            focus = options[next].id
                            if !multiple { select(options[next].id) }
                        }
                        return .handled
                    }
            }
        }.padding(2).background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: size.radius))
            .overlay { RoundedRectangle(cornerRadius: size.radius).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
            .opacity(enabled ? 1 : 0.5).accessibilityElement(children: .contain).accessibilityLabel(label)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: selected)
    }
    private func select(_ id: String) {
        guard enabled, options.contains(where: { $0.id == id && $0.enabled }) else { return }
        if multiple { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
        else { selected = [id] } // Repeated selection never clears a single-choice control.
    }
}

struct TahoeRadioGroup: View {
    let options: [TahoeChoice]
    @Binding var selection: String
    var label: String
    var size: TahoeControlSize = .regular
    @FocusState private var focus: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options) { option in
                Button { selection = option.id } label: {
                    HStack(spacing: 7) {
                        Circle().fill(TahoeDesign.content).overlay { Circle().fill(TahoeDesign.accent.opacity(selection == option.id ? 1 : 0)) }.frame(width: size.choiceSize, height: size.choiceSize)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.75) }
                            .overlay { if selection == option.id { Circle().fill(.white).frame(width: size == .mini ? 4 : 4.8, height: size == .mini ? 4 : 4.8) } }
                        Text(option.title).font(.system(size: size.fontSize))
                    }.frame(minHeight: 24).contentShape(Rectangle())
                }.buttonStyle(TahoePressStyle()).disabled(!option.enabled).focused($focus, equals: option.id)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selection == option.id ? [.isSelected] : [])
                    .onKeyPress { event in
                        let delta: Int
                        switch event.key { case .upArrow, .leftArrow: delta = -1; case .downArrow, .rightArrow: delta = 1; default: return .ignored }
                        if let next = TahoeMenuNavigation.next(from: options.firstIndex(where: { $0.id == option.id }), direction: delta, enabled: options.map(\.enabled)) {
                            selection = options[next].id; focus = selection
                        }
                        return .handled
                    }
            }
        }.accessibilityElement(children: .contain).accessibilityLabel(label)
    }
}

struct TahoeStepper: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var label: String
    var size: TahoeControlSize = .regular
    var wraps = false
    @State private var repetition: Task<Void, Never>?
    @GestureState private var holding = false
    @State private var pressed = 0
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.tahoeWindowActive) private var windowActive
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(spacing: 0) {
            arrow(1, symbol: "chevron.up")
            Divider()
            arrow(-1, symbol: "chevron.down")
        }.frame(width: size.stepperWidth, height: size.height).background(TahoeDesign.content, in: RoundedRectangle(cornerRadius: 5))
            .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.15), lineWidth: 0.75) }
            .overlay { RoundedRectangle(cornerRadius: 5).stroke(focused ? TahoeDesign.accent.opacity(0.35) : .clear, lineWidth: 3).padding(-2) }
            .focusable(enabled).focused($focused).focusEffectDisabled()
            .onKeyPress { event in
                guard enabled, windowVisible, windowActive else { return .ignored }
                switch event.key {
                case .upArrow: bump(1)
                case .downArrow: bump(-1)
                case .home: value = range.lowerBound
                case .end: value = range.upperBound
                default: return .ignored
                }
                return .handled
            }
            .onChange(of: windowVisible) { _, visible in if !visible { cancel() } }
            .onChange(of: holding) { _, holding in if !holding { cancel() } }
            .onChange(of: windowActive) { _, active in if !active { cancel() } }
            .onDisappear { cancel() }.onChange(of: enabled) { _, enabled in if !enabled { cancel() } }
            .onChange(of: phase) { _, phase in if phase != .active { cancel() } }
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value.formatted())
            .accessibilityAdjustableAction { if $0 == .increment { bump(1) } else { bump(-1) } }
    }
    private func arrow(_ direction: Int, symbol: String) -> some View {
        let allowed = enabled && (wraps || (direction > 0 ? value < range.upperBound : value > range.lowerBound))
        return Image(systemName: symbol).font(.system(size: 8, weight: .bold)).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pressed == direction ? Color.primary.opacity(0.1) : .clear).opacity(allowed ? 1 : 0.35)
            .contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).updating($holding) { _, state, _ in state = true }.onChanged { _ in
                guard allowed, pressed != direction else { return }
                cancel(); pressed = direction; focused = true
                guard bump(direction) else { cancel(); return }
                repetition = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(500))
                        var interval: Double = 100
                        while !Task.isCancelled {
                            guard enabled, bump(direction) else { cancel(); return }
                            interval = max(30, interval * 0.9)
                            try await Task.sleep(for: .milliseconds(interval))
                        }
                    } catch { }
                }
            }.onEnded { _ in cancel() })
    }
    @discardableResult private func bump(_ direction: Int) -> Bool {
        guard enabled else { return false }
        let next = TahoeNumeric.stepping(value, direction: direction, in: range, step: step, wraps: wraps)
        guard next != value else { return false }; value = next; return true
    }
    private func cancel() { repetition?.cancel(); repetition = nil; pressed = 0 }
}

struct TahoeCheckbox: View {
    let title: String
    @Binding var state: TahoeCheckState
    var size: TahoeControlSize = .regular
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button { state = state == .on ? .off : .on } label: {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: size == .regular ? 5.5 : size.choiceSize / 3)
                    .fill(TahoeDesign.content)
                    .overlay { RoundedRectangle(cornerRadius: size == .regular ? 5.5 : size.choiceSize / 3).fill(TahoeDesign.accent.opacity(state == .off ? 0 : 1)) }.frame(width: size.choiceSize, height: size.choiceSize)
                    .overlay { RoundedRectangle(cornerRadius: size == .regular ? 5.5 : size.choiceSize / 3).strokeBorder(.primary.opacity(0.18), lineWidth: 0.5) }
                    .overlay { if state != .off { Image(systemName: state == .mixed ? "minus" : "checkmark").font(.system(size: size.choiceSize * 0.6, weight: .bold)).foregroundStyle(.white) } }
                Text(title).font(.system(size: size.fontSize))
            }.frame(minHeight: max(24, size.height)).contentShape(Rectangle())
        }.buttonStyle(TahoePressStyle()).opacity(enabled ? 1 : 0.5)
            .accessibilityValue(state == .mixed ? "Mixed" : state == .on ? "Selected" : "Not selected")
    }
}

struct TahoeProgress: View {
    var value: Double?
    var height: CGFloat = 6
    var label = "Progress"
    var active = true
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Color.primary.opacity(0.12)).overlay(alignment: .leading) {
                if let value {
                    Capsule().fill(TahoeDesign.accent).frame(width: geometry.size.width * CGFloat(TahoeNumeric.value(value, in: 0...1)))
                } else if active && windowVisible && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        Capsule().fill(TahoeDesign.accent).frame(width: geometry.size.width * 0.3).offset(x: geometry.size.width * (phase * 1.3 - 0.3))
                    }
                } else { Capsule().fill(TahoeDesign.accent.opacity(0.6)).frame(width: geometry.size.width * 0.3) }
            }.clipShape(Capsule())
        }.frame(height: height).accessibilityElement(children: .ignore).accessibilityLabel(label)
            .accessibilityValue(value.map { "\(Int(TahoeNumeric.value($0, in: 0...1) * 100)) percent" } ?? "In progress")
    }
}

struct TahoeSpinner: View {
    var active = true
    var size: CGFloat = 16
    @Environment(\.tahoeWindowVisible) private var windowVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: !active || !windowVisible || reduceMotion)) { timeline in
            let phase = active && !reduceMotion ? Int(timeline.date.timeIntervalSinceReferenceDate * 12) % 12 : 0
            ZStack {
                ForEach(0..<12) { index in
                    Capsule().fill(Color.primary.opacity(0.15 + Double((index + phase) % 12) / 14))
                        .frame(width: size * 0.11, height: size * 0.25).offset(y: -size * 0.34).rotationEffect(.degrees(Double(index) * 30))
                }
            }
        }.frame(width: size, height: size).accessibilityLabel("In progress")
    }
}

struct TahoeBadge: View {
    let title: String
    var tint: Color = .secondary
    var body: some View { Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).frame(minHeight: 16).foregroundStyle(tint).background(tint.opacity(0.13), in: Capsule()) }
}

struct TahoeDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 6) { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(expanded ? 90 : 0)); Text(title).fontWeight(.medium); Spacer() }
            }.buttonStyle(TahoePressStyle()).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content().padding(.leading, 18).foregroundStyle(.secondary) }
        }.font(.system(size: 13))
    }
}

struct TahoeSettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title { Text(title).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 3) }
            content().tahoeGlassGroup().font(.system(size: 13)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(TahoeDesign.group, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
            if let footer { Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 3) }
        }
    }
}

