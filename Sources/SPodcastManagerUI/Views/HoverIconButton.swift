import SwiftUI

struct HoverIconButton: View {
    let systemName: String
    let helpText: String
    let isDestructive: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        systemName: String,
        helpText: String,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.helpText = helpText
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(borderColor, lineWidth: isHovered ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .help(helpText)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        if isDisabled {
            return Color.secondary.opacity(0.45)
        }
        if isDestructive && isHovered {
            return Color.red
        }
        if isHovered {
            return Color.primary
        }
        return Color.secondary
    }

    private var backgroundColor: Color {
        if isDisabled {
            return Color.clear
        }
        if isDestructive && isHovered {
            return Color.red.opacity(0.12)
        }
        if isHovered {
            return Color(NSColor.quaternaryLabelColor).opacity(0.14)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isDestructive && isHovered {
            return Color.red.opacity(0.28)
        }
        return Color(NSColor.separatorColor)
    }
}
