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
        field.text = text
        field.isSecureTextEntry = true
        field.keyboardType = .asciiCapable
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
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingDidEnd)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        Self.trace("create", field: field, bindingCount: text.count, identifier: identifier)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        Self.trace("update", field: field, bindingCount: text.count, identifier: identifier)
        // An in-flight keyboard edit owns the text until editing ends. A form
        // layout update must not replace it with an older binding snapshot.
        if !context.coordinator.editing, !field.isEditing, field.text != text { field.text = text }
    }

    private static func trace(_ event: String, field: UITextField, bindingCount: Int, identifier: String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["READER_UI_DIAGNOSTICS"] == "1" {
            NSLog("%@", "Reader secure-input diagnostic id=\(identifier) event=\(event) textCount=\(field.text?.count ?? 0) bindingCount=\(bindingCount) editing=\(field.isEditing) responder=\(field.isFirstResponder)")
        }
        #endif
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SecureEntry
        var editing = false
        init(_ parent: SecureEntry) { self.parent = parent }
        func textFieldDidBeginEditing(_ field: UITextField) { editing = true }
        func textFieldDidEndEditing(_ field: UITextField) {
            changed(field)
            editing = false
        }
        @objc func changed(_ field: UITextField) {
            SecureEntry.trace("change-before", field: field, bindingCount: parent.text.count, identifier: parent.identifier)
            parent.text = field.text ?? ""
            SecureEntry.trace("change-after", field: field, bindingCount: parent.text.count, identifier: parent.identifier)
        }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            SecureEntry.trace("replace-\(range.length)-with-\(string.count)", field: field, bindingCount: parent.text.count, identifier: parent.identifier)
            return true
        }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}
