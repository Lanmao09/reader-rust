import SwiftUI
import UIKit

enum ReadingTheme: String, CaseIterable, Identifiable {
    case paper, white, green, night
    var id: String { rawValue }
    var title: String { switch self { case .paper: return "书纸"; case .white: return "素白"; case .green: return "青绿"; case .night: return "夜读" } }
    var background: UIColor {
        switch self {
        case .paper: return UIColor(red: 0.97, green: 0.94, blue: 0.87, alpha: 1)
        case .white: return .white
        case .green: return UIColor(red: 0.88, green: 0.93, blue: 0.87, alpha: 1)
        case .night: return UIColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1)
        }
    }
    var foreground: UIColor { self == .night ? UIColor(white: 0.74, alpha: 1) : UIColor(white: 0.18, alpha: 1) }
}

struct ReadingTextView: UIViewRepresentable {
    let chapterID: String
    let content: String
    let fraction: Double
    let fontSize: Double
    let lineSpacing: Double
    let theme: ReadingTheme
    let useSerif: Bool
    let onProgress: (Double) -> Void
    let onToggle: () -> Void
    let onChapterStep: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.accessibilityLabel = "章节正文"
        view.accessibilityIdentifier = "reader.body"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.backgroundColor = theme.background
        let signature = "\(chapterID)|\(content.hashValue)|\(fontSize)|\(lineSpacing)|\(theme)|\(useSerif)"
        let changed = signature != coordinator.signature
        let horizontal = max(24, (view.bounds.width - 740) / 2)
        view.textContainerInset = UIEdgeInsets(top: 36, left: horizontal, bottom: 60, right: horizontal)
        if changed {
            coordinator.signature = signature
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = CGFloat(lineSpacing)
            paragraph.paragraphSpacing = CGFloat(fontSize * 0.65)
            paragraph.firstLineHeadIndent = CGFloat(fontSize * 2)
            let font = useSerif ? (UIFont(name: "SongtiSC-Regular", size: CGFloat(fontSize)) ?? .systemFont(ofSize: CGFloat(fontSize))) : .systemFont(ofSize: CGFloat(fontSize))
            coordinator.restoring = true
            view.attributedText = NSAttributedString(string: Self.plainText(content), attributes: [
                .font: font, .foregroundColor: theme.foreground, .paragraphStyle: paragraph,
            ])
            coordinator.restoring = false
        }
        if changed || (!view.isDragging && !view.isDecelerating && abs(coordinator.lastReported - fraction) > 0.0002) {
            let expectedSignature = signature
            DispatchQueue.main.async {
                guard coordinator.signature == expectedSignature else { return }
                view.layoutIfNeeded()
                coordinator.restoring = true
                let maximum = max(0, view.contentSize.height - view.bounds.height)
                view.setContentOffset(CGPoint(x: 0, y: maximum * CGFloat(fraction)), animated: false)
                coordinator.lastReported = fraction
                coordinator.restoring = false
            }
        }
    }
    static func plainText(_ content: String) -> String {
        var text = content.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</(?:p|div|h[1-6])>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</?[A-Za-z][^>]*>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "\n[ \t]*\n(?:[ \t]*\n)+", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReadingTextView
        var signature = ""
        var restoring = false
        var lastReported = 0.0
        init(_ parent: ReadingTextView) { self.parent = parent }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !restoring, scrollView.isDragging || scrollView.isDecelerating else { return }
            report(scrollView)
        }
        func report(_ view: UIScrollView) {
            let maximum = max(1, view.contentSize.height - view.bounds.height)
            lastReported = min(1, max(0, Double(view.contentOffset.y / maximum)))
            parent.onProgress(lastReported)
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let text = recognizer.view as? UITextView else { return true }
            return text.selectedTextRange?.isEmpty != false
        }
        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? UITextView, view.bounds.width > 0 else { return }
            let x = recognizer.location(in: view).x / view.bounds.width
            guard x < 0.22 || x > 0.78 else { parent.onToggle(); return }
            let step = max(80, view.bounds.height - 48) * (x < 0.22 ? -1 : 1)
            let maximum = max(0, view.contentSize.height - view.bounds.height)
            let target = view.contentOffset.y + step
            if target < -2 { parent.onChapterStep(-1); return }
            if target > maximum + 2 && view.contentOffset.y >= maximum - 2 { parent.onChapterStep(1); return }
            view.setContentOffset(CGPoint(x: 0, y: min(maximum, max(0, target))), animated: false)
            report(view)
        }
    }
}
