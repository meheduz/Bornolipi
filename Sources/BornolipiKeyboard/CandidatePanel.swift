#if canImport(InputMethodKit)
import AppKit
import BanglaEngine

/// The candidate window: a small non-activating panel under the caret with the roman text typed and
/// the Bangla candidates. It never becomes key, so the host app keeps receiving the keyboard.
final class CandidatePanel {
    static let shared = CandidatePanel()

    var onPick: ((Int) -> Void)?

    private let panel = FloatingPanel()
    private let stack = NSStackView()
    private let header = NSTextField(labelWithString: "")
    private var rows: [Row] = []
    private var shown: CandidateList?

    private init() {
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(3, after: header)
        panel.install(stack)
        // Not an accessibility element: with Full Keyboard Access on, macOS would try to focus it (mtgto/macSKK#115).
        panel.setAccessibilityElement(false)
    }

    func show(_ list: CandidateList, near caret: NSRect, clientLevel: Int) {
        if list != shown { update(list) }
        // Above the client's own window (Spotlight, full-screen apps), and never below menus.
        panel.level = NSWindow.Level(rawValue: max(clientLevel + 1, NSWindow.Level.popUpMenu.rawValue))
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(size)
        let screens = NSScreen.screens.map { CandidatePlacement.Screen(frame: $0.frame, visible: $0.visibleFrame) }
        panel.setFrameOrigin(CandidatePlacement.origin(size: size, caret: caret, screens: screens))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        shown = nil
    }

    var windowNumber: Int { panel.windowNumber }

    private func update(_ list: CandidateList) {
        shown = list
        header.stringValue = list.typed
        while rows.count < list.candidates.count {
            let row = Row { [weak self] index in self?.onPick?(index) }
            rows.append(row)
            stack.addArrangedSubview(row)
        }
        var width: CGFloat = 96
        for (i, row) in rows.enumerated() {
            row.isHidden = i >= list.candidates.count
            guard !row.isHidden else { continue }
            row.set(index: i, text: list.candidates[i], selected: i == list.selected, size: CGFloat(SettingsStore.shared.settings.candidateTextSize))
            width = max(width, row.naturalWidth)
        }
        for row in rows { row.width.constant = width }
        announce(list)
    }

    /// The panel stays out of VoiceOver's focus order (it must not take focus from the document),
    /// so VoiceOver users hear the selected candidate as an announcement instead, when it changes.
    private var lastAnnounced: String?
    private func announce(_ list: CandidateList) {
        guard NSWorkspace.shared.isVoiceOverEnabled, list.selected < list.candidates.count else { return }
        let text = "\(list.candidates[list.selected]), \(list.selected + 1) of \(list.candidates.count)"
        guard text != lastAnnounced else { return }
        lastAnnounced = text
        Accessibility.announce(text)
    }

    fileprivate final class Row: NSView {
        private let label = NSTextField(labelWithString: "")
        private let click: (Int) -> Void
        private var index = 0
        private var selected = false
        lazy var width = widthAnchor.constraint(equalToConstant: 96)
        lazy var height = heightAnchor.constraint(equalToConstant: 28)

        init(click: @escaping (Int) -> Void) {
            self.click = click
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 6
            label.font = .systemFont(ofSize: 17)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                height,
                width,
            ])
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        var naturalWidth: CGFloat { label.intrinsicContentSize.width + 20 }

        func set(index: Int, text: String, selected: Bool, size: CGFloat = 17) {
            if label.font?.pointSize != size {
                label.font = .systemFont(ofSize: size)
                height.constant = (size * 1.65).rounded()
            }
            self.index = index
            self.selected = selected
            label.stringValue = text
            setAccessibilityLabel(text)
            setAccessibilitySelected(selected)
            needsDisplay = true
            updateColors()
        }

        private func updateColors() {
            label.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
            effectiveAppearance.performAsCurrentDrawingAppearance {
                self.layer?.backgroundColor = self.selected ? NSColor.selectedContentBackgroundColor.cgColor : nil
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateColors()
        }

        override func mouseDown(with event: NSEvent) { click(index) }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func accessibilityPerformPress() -> Bool { click(index); return true }
    }
}

/// A borderless panel that floats over every Space and full-screen app and never takes focus,
/// with the system material behind its content (Liquid Glass on macOS 26 and later).
final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Puts `content` on the material, filling the panel.
    func install(_ content: NSView, cornerRadius: CGFloat = 10) {
        let holder = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            content.topAnchor.constraint(equalTo: holder.topAnchor),
            content.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        #if compiler(>=6.2)   // NSGlassEffectView needs the macOS 26 SDK (Xcode 26)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = holder
            contentView = glass
            return
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        holder.frame = effect.bounds
        holder.autoresizingMask = [.width, .height]
        effect.addSubview(holder)
        contentView = effect
    }
}

/// A brief "বাং" / "EN" bubble shown when the mode changes.
final class HUD {
    static let shared = HUD()
    private let panel = FloatingPanel()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    private init() {
        panel.ignoresMouseEvents = true
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.alignment = .center
        let box = NSStackView(views: [label])
        box.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        panel.install(box, cornerRadius: 9)
        panel.level = .popUpMenu
    }

    func flash(_ text: String, near rect: NSRect) {
        label.stringValue = text
        if NSWorkspace.shared.isVoiceOverEnabled { Accessibility.announce(text == "EN" ? "English" : "Bangla") }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 56, height: 32)
        panel.setContentSize(size)
        let screens = NSScreen.screens.map { CandidatePlacement.Screen(frame: $0.frame, visible: $0.visibleFrame) }
        panel.setFrameOrigin(CandidatePlacement.origin(size: size, caret: rect, screens: screens))
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    var windowNumber: Int { panel.windowNumber }
}
/// VoiceOver announcements from the keyboard's floating windows.
enum Accessibility {
    static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
#endif
