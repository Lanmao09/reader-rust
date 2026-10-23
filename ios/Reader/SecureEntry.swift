import SwiftUI
import UIKit

/// Keep one secure UITextField and its editing state across SwiftUI form updates.
struct SecureEntry: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType?
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.isSecureTextEntry = true
        field.textContentType = contentType
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.clearsOnBeginEditing = false
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .done
        field.accessibilityLabel = placeholder
        field.accessibilityIdentifier = identifier
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecureEntry
        init(_ parent: SecureEntry) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}
