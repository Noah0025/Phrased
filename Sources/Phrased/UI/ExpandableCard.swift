import SwiftUI

struct ExpandableCard<Header: View, Detail: View>: View {
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: (() -> Void)?
    @ViewBuilder var header: () -> Header
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    header()
                    Spacer()
                    if let onDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(PhrasedFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "settings.help.delete"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.vertical, PhrasedSpacing.xs)
                detail()
            }
        }
        .padding(PhrasedSpacing.sm + 2)
        .background(Color.primary.opacity(PhrasedOpacity.subtleFill))
        .clipShape(RoundedRectangle(cornerRadius: PhrasedRadius.sm))
        .overlay(RoundedRectangle(cornerRadius: PhrasedRadius.sm).strokeBorder(Color.primary.opacity(PhrasedOpacity.border), lineWidth: 0.5))
    }
}
