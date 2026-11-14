import SwiftUI

/// UIKit exposes keyboard modifiers on pointer gestures on iPadOS. Keep this
/// small input adapter separate from SwiftUI selection/layout/state ownership.
struct TahoePointerSurface: UIViewRepresentable {
    @Environment(\.tahoeWindowActive) private var active
    @Environment(\.tahoeWindowVisible) private var visible
    @Environment(\.isEnabled) private var enabled
    var feedback = true
    var click: (UIKeyModifierFlags) -> Void
    var doubleClick: () -> Void = {}
    var touchOpen: (() -> Void)?
    var drag: ((UIGestureRecognizer.State, CGPoint, CGSize) -> Void)?
    var context: ((CGPoint) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = TahoePointerFeedbackView(); view.feedback = feedback && active && visible && enabled
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.single(_:)))
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.double(_:)))
        double.numberOfTapsRequired = 2
        single.delegate = context.coordinator; double.delegate = context.coordinator
        view.addGestureRecognizer(single); view.addGestureRecognizer(double)
        if self.context != nil {
            let secondary = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.contextMenu(_:)))
            secondary.buttonMaskRequired = .secondary
            // buttonMaskRequired filters mouse buttons, but does not reject
            // direct finger taps. Keep touch context menus on long press.
            secondary.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            view.addGestureRecognizer(secondary)
            let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.contextMenu(_:)))
            view.addGestureRecognizer(hold)
        }
        if drag != nil {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
        }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        (view as? TahoePointerFeedbackView)?.feedback = feedback && active && visible && enabled
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TahoePointerSurface
        private var tapCount = 1
        private var direct = false
        init(_ parent: TahoePointerSurface) { self.parent = parent }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UITapGestureRecognizer && otherGestureRecognizer is UITapGestureRecognizer
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer is UITapGestureRecognizer { tapCount = touch.tapCount; direct = touch.type == .direct }
            return parent.enabled && parent.visible
        }
        @objc func single(_ recognizer: UITapGestureRecognizer) {
            guard parent.enabled && parent.visible && tapCount < 2 else { return }
            parent.click(recognizer.modifierFlags)
            if direct { parent.touchOpen?() }
        }
        @objc func double(_ recognizer: UITapGestureRecognizer) {
            guard parent.enabled && parent.visible, !(direct && parent.touchOpen != nil) else { return }
            parent.doubleClick()
        }
        @objc func contextMenu(_ recognizer: UIGestureRecognizer) {
            guard parent.enabled && parent.visible else { return }
            if recognizer is UILongPressGestureRecognizer && recognizer.state != .began { return }
            parent.context?(recognizer.location(in: recognizer.view))
        }
        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard parent.enabled && parent.visible else { return }
            let point = recognizer.location(in: recognizer.view)
            let translation = recognizer.translation(in: recognizer.view)
            parent.drag?(recognizer.state, point, CGSize(width: translation.x, height: translation.y))
        }
    }
}

struct TahoeTableColumn: Identifiable {
    var id: String
    var title: String
    var width: CGFloat
    var minimum: CGFloat = 80
}

/// macos-components' 24pt header / 28pt zebra-row table, extended with bounded
/// column resizing, sorting and native desktop multi-selection.
struct TahoeTable<Row, ID: Hashable, Cell: View>: View {
    let rows: [Row]
    let id: KeyPath<Row, ID>
    let columns: [TahoeTableColumn]
    let selected: Set<ID>
    var context: (Row) -> [TahoeMenuEntry] = { _ in [] }
    let sortColumn: String
    let ascending: Bool
    let select: (ID, UIKeyModifierFlags) -> Void
    let open: (Row) -> Void
    let sort: (String) -> Void
    @ViewBuilder let cell: (Row, String) -> Cell
    @State private var widths: [String: CGFloat] = [:]
    @State private var dragStart: CGFloat?
    @Environment(\.tahoeWindowActive) private var active
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(columns) { column in header(column) }
                        Spacer(minLength: 0)
                    }.frame(height: 40).background(TahoeDesign.window)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(rows.indices.map { TahoeTableRecord(index: $0, row: rows[$0], id: rows[$0][keyPath: id]) }) { record in
                                    let row = record.row
                                    let index = record.index
                                    let key = record.id
                                    HStack(spacing: 0) {
                                        ForEach(columns) { column in
                                            cell(row, column.id).font(.system(size: 13)).lineLimit(1)
                                                .padding(.horizontal, 12).frame(width: width(column), alignment: .leading)
                                        }
                                        Spacer(minLength: 0)
                                    }.frame(height: 44)
                                        .foregroundStyle(selected.contains(key) && active ? Color.white : .primary)
                                        .background(selected.contains(key) ? active ? TahoeDesign.accent : Color.primary.opacity(0.1) : index % 2 == 0 ? Color.clear : Color.primary.opacity(0.035))
                                        .overlay {
                                            GeometryReader { geometry in
                                                TahoePointerSurface(click: { select(key, $0) }, doubleClick: { open(row) }, touchOpen: { open(row) }, context: { point in
                                                    if !selected.contains(key) { select(key, []) }
                                                    let frame = geometry.frame(in: .named("tahoe-desktop"))
                                                    TahoeMenuCoordinator.shared.show(anchor: CGRect(x: frame.minX + point.x, y: frame.minY + point.y, width: 1, height: 1), entries: context(row))
                                                })
                                            }
                                        }
                                        .accessibilityElement(children: .combine).accessibilityAddTraits(selected.contains(key) ? [.isSelected, .isButton] : [.isButton])
                                        .accessibilityAction { select(key, []) }.accessibilityAction(named: "Open") { open(row) }
                                        .id(key)
                                }
                            }.frame(maxWidth: .infinity)
                        }.onChange(of: selected) { _, selected in if selected.count == 1, let key = selected.first { proxy.scrollTo(key) } }
                    }
                }.frame(width: max(geometry.size.width, columns.reduce(CGFloat(0)) { $0 + width($1) })).frame(height: geometry.size.height)
            }
        }
    }
    private func width(_ column: TahoeTableColumn) -> CGFloat { widths[column.id] ?? column.width }
    private func header(_ column: TahoeTableColumn) -> some View {
        HStack(spacing: 0) {
            Button { sort(column.id) } label: {
                HStack(spacing: 4) {
                    Text(column.title).lineLimit(1)
                    if sortColumn == column.id { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
                    Spacer(minLength: 0)
                }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 12)
            }.buttonStyle(TahoePressStyle()).accessibilityLabel("Sort by \(column.title)")
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 6).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                    if dragStart == nil { dragStart = width(column) }
                    widths[column.id] = max(column.minimum, min(600, (dragStart ?? width(column)) + value.translation.width))
                }.onEnded { _ in dragStart = nil })
                .accessibilityLabel("Resize \(column.title) column")
                .accessibilityAdjustableAction { change in widths[column.id] = min(600, max(column.minimum, width(column) + (change == .increment ? 20 : -20))) }
        }.frame(width: width(column))
    }
}

private struct TahoeTableRecord<Row, ID: Hashable>: Identifiable { var index: Int; var row: Row; var id: ID }


/// Visual feedback only: existing tap, double-click and drag recognizers own input.
private final class TahoePointerFeedbackView: UIView {
    var feedback = true { didSet { if !feedback { pressed = false; hovered = false; backgroundColor = .clear } } }
    private var pressed = false
    private var hovered = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = 6
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func hover(_ recognizer: UIHoverGestureRecognizer) {
        hovered = recognizer.state == .began || recognizer.state == .changed
        refresh()
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event); pressed = true; refresh()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        pressed = touches.first.map { bounds.contains($0.location(in: self)) } ?? false; refresh()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event); pressed = false; refresh()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event); pressed = false; refresh()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { pressed = false; hovered = false; backgroundColor = .clear }
    }
    private func refresh() {
        let color = UIColor.label.withAlphaComponent(feedback ? (pressed ? 0.13 : hovered ? 0.055 : 0) : 0)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.10,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.backgroundColor = color }
    }
}
