#if canImport(UIKit)
import SwiftUI
import UIKit
import GameController

/// Chat input backed by UITextView so Return never ends editing: the delegate catches "\n",
/// calls `onReturn` (send) and returns false, so the view never resigns first responder and
/// the keyboard stays up. Grows to ~4 lines, then scrolls. Tab (hardware) calls `onTab`.
struct UMComposerField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var enabled: Bool
    var textColor: UIColor
    var maxLength: Int
    var onReturn: () -> Void
    var onTab: () -> Bool = { false }
    /// Option+arrow game shortcuts; they take priority over text navigation while typing.
    var onShortcut: (UMGameShortcut) -> Void = { _ in }

    static let font = UIFont.preferredFont(forTextStyle: .body)
    static let maxLines: CGFloat = 4

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UMComposerTextView()
        tv.onShortcut = { [weak coordinator = context.coordinator] s in coordinator?.parent.onShortcut(s) }
        tv.delegate = context.coordinator
        tv.font = Self.font
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.returnKeyType = .send
        tv.enablesReturnKeyAutomatically = false
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let label = UILabel()
        label.font = Self.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor),
            label.topAnchor.constraint(equalTo: tv.topAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: tv.widthAnchor),
        ])
        context.coordinator.placeholderLabel = label
        context.coordinator.applyTraits(tv)
        context.coordinator.observeKeyboards(tv)
        return tv
    }

    /// iPad + hardware keyboard: hide the floating shortcuts bar (undo/redo/paste, keyboard
    /// options, predictions). Empty bar button groups remove the shortcut buttons; turning off
    /// autocorrect/spellcheck/inline prediction removes the suggestion strip, so the bar has
    /// nothing to show. iPhone and iPad with the on-screen keyboard keep their defaults.
    /// The floating dictation mic has no public opt-out (dictation can't be disabled per field).
    ///
    /// `hardware` is only true once UIKit has actually presented the hardware-keyboard UI (no
    /// software keyboard on screen) while GameController also reports a keyboard. GCKeyboard alone
    /// can report one when UIKit still shows the on-screen keyboard or has none to show; stripping
    /// the bar then removed the iPadOS keyboard button, so tapping the composer brought up nothing.
    static func applyHardwareKeyboardTraits(_ tv: UITextView, hardware: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let auto: UITextAutocorrectionType = hardware ? .no : .default
        let spell: UITextSpellCheckingType = hardware ? .no : .default
        let inline: UITextInlinePredictionType = hardware ? .no : .default
        if tv.autocorrectionType != auto { tv.autocorrectionType = auto }
        if tv.spellCheckingType != spell { tv.spellCheckingType = spell }
        if tv.inlinePredictionType != inline { tv.inlinePredictionType = inline }
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text {
            tv.text = text
            // Chips/autofill replace the text: keep the cursor at the end.
            let end = tv.endOfDocument
            tv.selectedTextRange = tv.textRange(from: end, to: end)
        }
        tv.textColor = textColor
        tv.isEditable = enabled
        context.coordinator.placeholderLabel?.text = placeholder
        context.coordinator.placeholderLabel?.textColor = enabled ? .placeholderText : textColor
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        if isFocused, !tv.isFirstResponder, enabled, tv.window != nil {
            DispatchQueue.main.async { tv.becomeFirstResponder() }
        } else if !isFocused, tv.isFirstResponder {
            tv.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? tv.bounds.width
        guard width > 0 else { return nil }
        let fitting = tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let line = (tv.font ?? Self.font).lineHeight
        let maxH = ceil(line * Self.maxLines)
        let h = min(max(fitting, ceil(line)), maxH)
        let scroll = fitting > maxH
        if tv.isScrollEnabled != scroll { DispatchQueue.main.async { tv.isScrollEnabled = scroll } }
        return CGSize(width: width, height: h)
    }

    /// Text view that claims Option+arrows before UIKit's word/paragraph navigation. No
    /// discoverability titles here: the game screen's SwiftUI shortcuts list them in the
    /// Cmd-hold overlay, so they aren't shown twice.
    final class UMComposerTextView: UITextView {
        var onShortcut: ((UMGameShortcut) -> Void)?

        override var keyCommands: [UIKeyCommand]? {
            let pairs: [(String, Selector)] = [
                (UIKeyCommand.inputLeftArrow, #selector(prevPhase)),
                (UIKeyCommand.inputRightArrow, #selector(nextPhase)),
                (UIKeyCommand.inputUpArrow, #selector(chatTop)),
                (UIKeyCommand.inputDownArrow, #selector(chatBottom)),
            ]
            let mine = pairs.map { input, action -> UIKeyCommand in
                let c = UIKeyCommand(input: input, modifierFlags: .alternate, action: action)
                c.wantsPriorityOverSystemBehavior = true
                c.attributes = .hidden
                return c
            }
            return mine + (super.keyCommands ?? [])
        }

        @objc private func prevPhase() { onShortcut?(.previousPhase) }
        @objc private func nextPhase() { onShortcut?(.nextPhase) }
        @objc private func chatTop() { onShortcut?(.chatTop) }
        @objc private func chatBottom() { onShortcut?(.chatBottom) }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: UMComposerField
        weak var placeholderLabel: UILabel?
        private var keyboardObservers: [NSObjectProtocol] = []
        /// The system's own bar groups, saved at the moment we clear them (not at view creation,
        /// when UIKit hasn't populated them yet; restoring that empty snapshot was what made the
        /// show-keyboard / dictation button vanish until a rotation rebuilt the bar).
        private var savedGroups: (leading: [UIBarButtonItemGroup], trailing: [UIBarButtonItemGroup])?

        /// Confirmed hardware-keyboard mode (see applyHardwareKeyboardTraits). Starts false so the
        /// first focus always gets the stock bar and on-screen keyboard behavior.
        private var hardwareMode = false

        func applyTraits(_ tv: UITextView) {
            guard UIDevice.current.userInterfaceIdiom == .pad else { return }
            UMComposerField.applyHardwareKeyboardTraits(tv, hardware: hardwareMode)
            let item = tv.inputAssistantItem
            if hardwareMode, savedGroups == nil {
                savedGroups = (item.leadingBarButtonGroups, item.trailingBarButtonGroups)
                item.leadingBarButtonGroups = []
                item.trailingBarButtonGroups = []
            } else if !hardwareMode, let saved = savedGroups {
                item.leadingBarButtonGroups = saved.leading
                item.trailingBarButtonGroups = saved.trailing
                savedGroups = nil
            }
            if tv.isFirstResponder { tv.reloadInputViews() }
        }

        private func setHardwareMode(_ on: Bool, _ tv: UITextView) {
            guard on != hardwareMode else { return }
            hardwareMode = on
            applyTraits(tv)
        }
        init(_ parent: UMComposerField) { self.parent = parent }

        deinit { keyboardObservers.forEach(NotificationCenter.default.removeObserver) }

        /// Live: keyboard frame changes decide software vs hardware; attach/detach resets to stock
        /// so UIKit can bring up (or drop) the on-screen keyboard, then the next frame re-decides.
        func observeKeyboards(_ tv: UITextView) {
            guard UIDevice.current.userInterfaceIdiom == .pad, keyboardObservers.isEmpty else { return }
            for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
                keyboardObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak tv] _ in
                    guard let self, let tv else { return }
                    MainActor.assumeIsolated { self.setHardwareMode(false, tv) }
                })
            }
            for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
                         UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
                         UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            keyboardObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak tv] note in
                guard let self, let tv else { return }
                let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
                MainActor.assumeIsolated {
                    guard tv.isFirstResponder else { self.setHardwareMode(false, tv); return }
                    let screen = tv.window?.screen.bounds ?? UIScreen.main.bounds
                    let visible = screen.intersection(end).height
                    // Only when nothing at all is on screen. A collapsed / minimized / floating software
                    // keyboard still shows the slim bar (visible > 0); clearing it there removed the
                    // show-keyboard / dictation button for good. Any visible frame restores the stock bar.
                    self.setHardwareMode(GCKeyboard.coalesced != nil && visible < 1, tv)
                }
            })
            }
        }

        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            applyTraits(textView)
            return true
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onReturn()
                return false
            }
            if text == "\t" {
                // Hardware Tab only ever completes; never insert a literal tab, even when nothing matched.
                _ = parent.onTab()
                return false
            }
            if text.contains(where: \.isNewline) {
                // Pasted multi-line text: flatten to one line (chat messages are single-line).
                let flat = text.replacingOccurrences(of: "\r\n", with: " ")
                    .components(separatedBy: .newlines).joined(separator: " ")
                if let r = Range(range, in: textView.text ?? "") {
                    let next = (textView.text ?? "").replacingCharacters(in: r, with: flat)
                    parent.text = String(next.prefix(parent.maxLength))
                }
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let capped = String((textView.text ?? "").prefix(parent.maxLength))
            if capped != textView.text { textView.text = capped }
            if parent.text != capped { parent.text = capped }
            placeholderLabel?.isHidden = !capped.isEmpty
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Next focus starts from the stock bar again.
            setHardwareMode(false, textView)
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
#endif
