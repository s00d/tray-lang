import SwiftUI

struct SymbolEditRowView: View {
    @Binding var from: String
    @Binding var to: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            TextField("From", text: $from)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
            
            TextField("To", text: $to)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity)
            
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }
}


