import SwiftUI

enum GroupBadgeSize {
    case tiny      // Top bar
    case mini      // Connection row in sidebar
    case small     // Group filter chips & headers
    case regular   // Form header & editor
}

typealias TagBadgeSize = GroupBadgeSize

/// A stylized badge component for connection groups / environments.
struct ConnectionGroupBadge: View {
    @Environment(AppState.self) private var appState: AppState?
    let group: String
    var size: GroupBadgeSize = .mini
    var isRowSelected: Bool = false
    var onRemove: (() -> Void)? = nil
    
    private var currentHex: String {
        if let appState = appState {
            return appState.groupColorHex(for: group)
        }
        return ConnectionStore.shared.groupColorHex(for: group)
    }
    
    private var colors: (bg: Color, text: Color, border: Color) {
        let baseColor = Color(hex: currentHex)
        return (
            bg: baseColor.opacity(0.18),
            text: baseColor,
            border: baseColor.opacity(0.55)
        )
    }
    
    var body: some View {
        HStack(spacing: size == .regular ? 4 : 2) {
            Text(group.uppercased())
                .font(font)
                .fontWeight(.bold)
                .lineLimit(1)
            
            if let onRemove = onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: removeIconSize, weight: .bold))
                        .foregroundColor(textColor.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: size == .regular ? 1 : 0.8)
        )
    }
    
    private var font: Font {
        switch size {
        case .tiny: return .system(size: 7, weight: .bold)
        case .mini: return .system(size: 8, weight: .bold)
        case .small: return .system(size: 9.5, weight: .bold)
        case .regular: return .system(size: 11, weight: .bold)
        }
    }
    
    private var removeIconSize: CGFloat {
        switch size {
        case .tiny, .mini: return 6
        case .small: return 7
        case .regular: return 9
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .tiny: return 3
        case .mini: return 4
        case .small: return 6
        case .regular: return 8
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .tiny: return 1
        case .mini: return 1.5
        case .small: return 2.5
        case .regular: return 4
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .tiny: return 2.5
        case .mini: return 3
        case .small: return 4
        case .regular: return 5
        }
    }
    
    private var textColor: Color {
        if isRowSelected {
            return .white
        }
        return colors.text
    }
    
    private var backgroundColor: Color {
        if isRowSelected {
            return Color.white.opacity(0.2)
        }
        return colors.bg
    }
    
    private var borderColor: Color {
        if isRowSelected {
            return Color.clear
        }
        return colors.border
    }
}

// Compatibility alias
typealias ConnectionTagBadge = ConnectionGroupBadge

/// A layout that arranges subviews horizontally and wraps to subsequent lines when space runs out.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
