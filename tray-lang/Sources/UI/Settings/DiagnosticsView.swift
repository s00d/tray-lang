import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var testText = ""
    @State private var transformedText = ""
    
    var body: some View {
        List {
            Section {
                TextField("Input text…", text: $testText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...12)

                Button("Convert") {
                    transformedText = coordinator.textTransformer.transformText(testText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(testText.isEmpty)

                if !transformedText.isEmpty {
                    Text(transformedText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            } header: {
                Text("Text Conversion Test")
            } footer: {
                Text("Enter text to test the current symbol replacement rules.")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


