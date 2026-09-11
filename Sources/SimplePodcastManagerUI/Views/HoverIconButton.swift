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
            HoverIconLabel(
                systemName: systemName,
                isHovered: isHovered,
                isDestructive: isDestructive,
                isDisabled: isDisabled,
                isActive: false
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct HoverIconLabel: View {
    let systemName: String
    let isHovered: Bool
    let isDestructive: Bool
    let isDisabled: Bool
    let isActive: Bool

    var body: some View {
        icon
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: isHovered ? 1 : 0)
            )
    }

    @ViewBuilder
    private var icon: some View {
        if isActive {
            Image(systemName: systemName)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.blue, foregroundColor)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foregroundColor)
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

struct HoverIconMenu<Content: View>: View {
    let systemName: String
    let helpText: String
    let isActive: Bool
    @ViewBuilder let content: Content

    @State private var isHovered = false

    init(
        systemName: String,
        helpText: String,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.systemName = systemName
        self.helpText = helpText
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        Menu {
            content
        } label: {
            HoverIconLabel(
                systemName: systemName,
                isHovered: isHovered,
                isDestructive: false,
                isDisabled: false,
                isActive: isActive
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
        .accessibilityLabel(helpText)
        .onHover { isHovered = $0 }
    }
}
