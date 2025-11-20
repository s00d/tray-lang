//
//  ExclusionRowView.swift
//  tray-lang
//
//  Created for tray-lang project
//

import SwiftUI

struct ExclusionRowView: View {
    let app: ExcludedApp
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(nsImage: app.appIcon)
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading) {
                Text(app.name)
                    .fontWeight(.semibold)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}


