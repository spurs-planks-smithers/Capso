// App/Feedback/FeedbackHelpOverlay.swift
import AnnotationKit
import AppKit
import KeyboardShortcuts
import SwiftUI

/// What the user does now in a feedback session. The help box lists the
/// keys for it.
enum FeedbackHelpStage {
    case selecting
    case marking
    case notes
    case between
}

/// Fork: a see-through box at the top right of the screen that lists the keys
/// for the current stage, from the feedback hotkey until the session ends
/// (Drew, 2026-10-21).
///
/// It never takes clicks or focus. `sharingType = .none` keeps it out of
/// screenshots and screen recordings. `FeedbackController` also hides it
/// before the feedback hotkey freezes the screen.
@MainActor
final class FeedbackHelpOverlay {
    /// Text size in points: 22, up from 14 (Drew, 2026-10-22).
    static let textSize: CGFloat = 22
    /// Box width, padding, and spacing grow with the text, so no line wraps.
    static let scale = textSize / 14
    static let width: CGFloat = (320 * scale).rounded()
    /// The box and its text draw at half opacity, so the screen shows
    /// through (Drew, 2026-10-22).
    static let opacity: CGFloat = 0.5
    /// Space between the box and the screen's top and right edges.
    static let margin: CGFloat = 12

    private var panel: NSPanel?
    private var hostingView: NSHostingView<FeedbackHelpView>?

    /// `document` is the inline editor's marks, so the Esc line can follow
    /// them. It is nil in the full editor, which has no arrow or Esc keys
    /// from the fork.
    func show(_ stage: FeedbackHelpStage, document: AnnotationDocument?, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        let panel = self.panel ?? makePanel()
        let view = FeedbackHelpView(
            stage: stage,
            document: document,
            captureShortcut: KeyboardShortcuts.getShortcut(for: .feedbackCapture)?.description
        )
        hostingView?.rootView = view
        let size = hostingView?.fittingSize ?? .zero
        let visible = screen.visibleFrame
        panel.setFrame(NSRect(
            x: visible.maxX - size.width - Self.margin,
            y: visible.maxY - size.height - Self.margin,
            width: size.width,
            height: size.height
        ), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the frozen screen and the selection overlay (`.screenSaver`)
        // and the capture toolbar (`.screenSaver + 2`).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.sharingType = .none
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = Self.opacity
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Light text on a dark glass reads over any screen content.
        panel.appearance = NSAppearance(named: .darkAqua)

        // `.active`, because this app is usually not the active app, and an
        // inactive effect view draws flat gray.
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = (10 * Self.scale).rounded()
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        let hostingView = NSHostingView(rootView: FeedbackHelpView(stage: .between, document: nil, captureShortcut: nil))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: glass.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        panel.contentView = glass
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }
}

struct FeedbackHelpView: View {
    let stage: FeedbackHelpStage
    let document: AnnotationDocument?
    let captureShortcut: String?

    private struct Line: Identifiable {
        let key: String
        let action: String
        var id: String { key }
    }

    private var title: String {
        switch stage {
        case .selecting: "Select an area"
        case .marking: "Mark the capture"
        case .notes: "Add notes"
        case .between: "Session active"
        }
    }

    private var lines: [Line] {
        switch stage {
        case .selecting:
            return [
                Line(key: "Drag", action: "Select an area"),
                Line(key: "Esc", action: "Cancel"),
            ]
        case .marking:
            var lines = [
                Line(key: "C or N", action: "Numbered circle"),
                Line(key: "A, R, T", action: "Arrow, box, text"),
                Line(key: "Delete", action: "Remove selected mark"),
                Line(key: "⌘S", action: "Save, then add notes"),
            ]
            if let document {
                lines.insert(Line(key: "← →", action: "Undo, redo"), at: 2)
                // Reading `objects` here updates the line as marks come and go.
                lines.append(document.objects.isEmpty
                    ? Line(key: "Esc", action: "Copy screenshot, close")
                    : Line(key: "Esc", action: "Step back"))
            }
            return lines
        case .notes:
            return [
                Line(key: "Return", action: "Save, go on"),
                Line(key: "Esc", action: "Skip this step"),
                Line(key: "↑ ↓", action: "Back, forward"),
                Line(key: "← →", action: "Back, forward at text edge"),
            ]
        case .between:
            return [
                Line(key: captureShortcut ?? "No shortcut", action: "Capture another area"),
                Line(key: "\(ForkBranding.shortName) menu", action: "Copy prompt, end session"),
            ]
        }
    }

    var body: some View {
        let size = FeedbackHelpOverlay.textSize
        let scale = FeedbackHelpOverlay.scale
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text(verbatim: "\(ForkBranding.name): \(title)")
                .font(.system(size: size, weight: .bold))
            Grid(alignment: .leading, horizontalSpacing: 14 * scale, verticalSpacing: 5 * scale) {
                ForEach(lines) { line in
                    GridRow {
                        Text(verbatim: line.key)
                            .font(.system(size: size, weight: .semibold))
                        Text(verbatim: line.action)
                            .font(.system(size: size))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14 * scale)
        .frame(width: FeedbackHelpOverlay.width, alignment: .leading)
    }
}
