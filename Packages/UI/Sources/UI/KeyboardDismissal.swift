import SwiftUI
import UIKit

// MARK: - Keyboard dismissal
// The decimal/number pads used for money entry have NO return key, so
// without this there is literally no way to close the keyboard — the bug
// the user hit on every tab. Two affordances, one modifier:
//  - a "Done" button in a toolbar above the keyboard,
//  - dragging any scrollable content dismisses immediately.
// A tap-anywhere gesture was deliberately NOT used: a simultaneous tap
// recognizer also fires when tapping INTO a text field, dismissing the
// keyboard the moment it opens.
public extension View {
    func dismissableKeyboard() -> some View {
        self
            .scrollDismissesKeyboard(.immediately)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .font(.headline)
                }
            }
    }
}
