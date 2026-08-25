//
//  ChromeSearchField.swift
//  Nanyin
//

import SwiftUI

struct ChromeSearchField: View {
    @Binding var text: String
    let style: ChromeSearchStyle
    var onTextChange: (String) -> Void = { _ in }
    var onSubmit: (String) -> Void = { _ in }
    @Environment(\.appTheme) private var theme

    private var resolvedStyle: ChromeSearchStyle {
        var resolved = style
        resolved.palette = theme.chrome.palette
        return resolved
    }

    var body: some View {
        ClassicChromeSearchFieldRepresentable(
            text: $text,
            style: resolvedStyle,
            onTextChange: onTextChange,
            onSubmit: onSubmit
        )
        .frame(width: resolvedStyle.size.width, height: resolvedStyle.size.height)
    }
}

private struct ClassicChromeSearchFieldRepresentable: NSViewRepresentable {
    @Binding var text: String
    let style: ChromeSearchStyle
    let onTextChange: (String) -> Void
    let onSubmit: (String) -> Void

    func makeNSView(context: Context) -> ClassicChromeSearchFieldView {
        ClassicChromeSearchFieldView()
    }

    func updateNSView(_ view: ClassicChromeSearchFieldView, context: Context) {
        view.style = style
        view.onTextChange = { value in
            text = value
            onTextChange(value)
        }
        view.onSubmit = onSubmit
        view.text = text
    }
}
