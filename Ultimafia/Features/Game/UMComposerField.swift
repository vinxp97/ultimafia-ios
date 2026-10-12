#if canImport(UIKit)
import SwiftUI
import UIKit

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

    static let font = UIFont.preferredFont(forTextStyle: .body)
    static let maxLines: CGFloat = 4

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
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
        return tv
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
            DispatchQueue.main.async { tv.resignFirstResponder() }
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

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: UMComposerField
        weak var placeholderLabel: UILabel?
        init(_ parent: UMComposerField) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onReturn()
                return false
            }
            if text == "\t" { return !parent.onTab() }
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
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
#endif
