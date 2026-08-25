//
//  ThemeSettingsView.swift
//  Nanyin
//

import SwiftUI

struct ThemeSettingsView: View {
    @AppStorage(AppThemeID.preferenceKey)
    private var storedThemeID = AppThemeID.nanyinDark.rawValue

    var body: some View {
        Form {
            Picker("Appearance", selection: selection) {
                ForEach(AppThemeID.allCases) { themeID in
                    Text(themeID.displayName)
                        .tag(themeID)
                }
            }
            .pickerStyle(.radioGroup)

            Text("Classic 2010 is an independent Nanyin theme inspired by early desktop music players.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(20)
    }

    private var selection: Binding<AppThemeID> {
        Binding(
            get: { AppThemeID(storedValue: storedThemeID) },
            set: { storedThemeID = $0.rawValue }
        )
    }
}
