import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var testText = ""
    @State private var transformedText = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Text Conversion Test")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Enter text to test the current symbol replacement rules.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField("Input text...", text: $testText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...10)
            
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
                    .cornerRadius(8)
                    .textSelection(.enabled)
            }
            
            Spacer()
        }
        .padding()
    }
}


