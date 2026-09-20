import SwiftUI

@MainActor
final class AssistantHubNavigation: ObservableObject {
    @Published var showTodosRequest = UUID()
}

struct AssistantHubView: View {
    @ObservedObject var store: AssistantStore
    @ObservedObject var captureState: InboxCaptureState
    @ObservedObject var navigation: AssistantHubNavigation

    @State private var selectedSection: Section = .inbox

    private enum Section: String, CaseIterable, Identifiable {
        case inbox = "Inbox"
        case todos = "Todo"
        case notes = "Notes"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .inbox: return "tray"
            case .todos: return "checkmark.circle"
            case .notes: return "note.text"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sectionBar
            Divider()

            Group {
                switch selectedSection {
                case .inbox:
                    QuickCaptureView(
                        store: store,
                        captureState: captureState
                    )
                case .todos:
                    TodoListView(
                        store: store,
                        onCreate: { selectedSection = .inbox }
                    )
                case .notes:
                    NotesListView(
                        store: store,
                        onCreate: { selectedSection = .inbox }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(Color.narcBackground)
        .onChange(of: navigation.showTodosRequest) { _, _ in selectedSection = .todos }
    }

    private var header: some View {
        HStack(spacing: NarcSpacing.md) {
            Image(systemName: "sparkles")
                .font(.narcTitle)
                .foregroundColor(.narcAccent)

            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text("Assistant")
                    .font(.narcTitle)
                    .foregroundColor(.narcText)
                Text("记录、查找并处理你的个人事项")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }

            Spacer()

            Button {
                selectedSection = .inbox
            } label: {
                Label("随手记", systemImage: "plus")
                    .font(.narcBody)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("打开随手箱")
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.vertical, NarcSpacing.lg)
    }

    private var sectionBar: some View {
        HStack(spacing: NarcSpacing.sm) {
            ForEach(Section.allCases) { section in
                Button {
                    withAnimation(.narcSnap) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: NarcSpacing.sm) {
                        Image(systemName: section.icon)
                        Text(section.rawValue)
                        Text("\(count(for: section))")
                            .font(.narcMonoSmall)
                            .foregroundColor(
                                selectedSection == section ? .narcAccent : .narcTextFaint
                            )
                    }
                    .font(.narcBody)
                    .foregroundColor(
                        selectedSection == section ? .narcAccent : .narcTextMuted
                    )
                    .padding(.horizontal, NarcSpacing.md)
                    .padding(.vertical, NarcSpacing.sm)
                    .background(
                        Capsule()
                            .fill(
                                selectedSection == section
                                    ? Color.narcAccent.opacity(0.14)
                                    : Color.clear
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开 \(section.rawValue)")
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }

            Spacer()
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.bottom, NarcSpacing.md)
    }

    private func count(for section: Section) -> Int {
        switch section {
        case .inbox:
            return store.inboxItems.count
        case .todos:
            return store.incompleteTodos.count
        case .notes:
            return store.notes.count
        }
    }
}
