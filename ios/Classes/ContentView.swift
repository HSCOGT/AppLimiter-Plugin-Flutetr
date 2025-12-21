import SwiftUI


import FamilyControls

@available(iOS 15.0, *)
struct ContentView: View {
    var applyLocally: Bool

    // Property for the dismissal callback
    var onDismiss: ((_ encodedData: String?) -> Void)?

    @EnvironmentObject var model: MyModel
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                FamilyActivityPicker(selection: $model.selectionToDiscourage)
            }
            .navigationBarTitle("Select Apps", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                    onDismiss?(nil)
                },
                trailing: Button("Done") {
                    // 1. Only apply locally if flag is true
                    if applyLocally {
                        model.setShieldRestrictions()
                    }
                    
                    // 2. Encode the selection to send back to Flutter
                    let encodedString = model.getEncodedSelection()
                    
                    presentationMode.wrappedValue.dismiss()
                    onDismiss?(encodedString)
                }
            )
        }
    }
}

@available(iOS 15.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(applyLocally: true, onDismiss: { _ in })
            .environmentObject(MyModel.shared)
    }
}
