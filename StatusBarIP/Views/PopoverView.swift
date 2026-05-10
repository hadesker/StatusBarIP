import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var store: IPStore
    let openSettings: () -> Void

    private let maxListHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ipList

            Divider()

            footer
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: store.visibleEntries)
        .animation(.easeInOut(duration: 0.18), value: store.copiedID)
    }

    private var ipList: some View {
        Group {
            if store.visibleEntries.count > 4 {
                ScrollView {
                    ipListContent
                }
                .frame(maxHeight: maxListHeight)
            } else {
                ipListContent
            }
        }
    }

    private var ipListContent: some View {
        LazyVStack(spacing: 6) {
            ForEach(store.visibleEntries) { entry in
                IPRow(entry: entry, copied: store.copiedID == entry.id) {
                    store.copy(entry)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Status Bar IP")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PopoverIconButton(systemName: "arrow.clockwise", help: "Refresh") {
                store.refreshAll()
            }

            PopoverIconButton(systemName: "gearshape", help: "Settings") {
                openSettings()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: store.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.lastError == nil ? .green : .orange)

            Text(store.lastError ?? lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        if let entry = store.statusEntry {
            return "Showing \(entry.displayTitle)"
        }
        return "No visible IPs"
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = store.lastUpdated else {
            return "Waiting for first public IP fetch"
        }
        return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }
}

private struct PopoverIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isHovering ? Color.primary.opacity(0.11) : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.05 : 1)
        .pointerOnHover()
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

private struct IPRow: View {
    let entry: IPEntry
    let copied: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var isCopyHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(entry.kind.tint.opacity(isHovering ? 0.24 : 0.16))
                    Image(systemName: entry.kind.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(entry.kind.tint)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(entry.address)
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(entry.address == "Unavailable" ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(copied ? .green : (isCopyHovering || isHovering ? .primary : .secondary))
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isCopyHovering ? Color.primary.opacity(0.16) : (isHovering ? Color.primary.opacity(0.1) : Color.clear))
                    }
                    .scaleEffect(isCopyHovering ? 1.08 : 1)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeOut(duration: 0.14), value: isCopyHovering)
                    .onHover { isCopyHovering = $0 }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.035))
            }
        }
        .buttonStyle(.plain)
        .pointerOnHover()
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .disabled(entry.address == "Unavailable")
        .help("Copy \(entry.address)")
    }
}

private extension View {
    func pointerOnHover() -> some View {
        onHover { isInside in
            if isInside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
