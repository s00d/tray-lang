import SwiftUI

struct SettingsRow<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(iconColor.gradient)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            content
        }
        .padding(.vertical, 8)
    }
}


