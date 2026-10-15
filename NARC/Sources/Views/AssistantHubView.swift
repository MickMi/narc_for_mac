import SwiftUI

@MainActor
final class AssistantHubNavigation: ObservableObject {
    @Published var showTodosRequest = UUID()
}

struct AssistantHubView: View {
    @ObservedObject var store: AssistantStore
    @ObservedObject var captureState: InboxCaptureState
    @ObservedObject var navigation: AssistantHubNavigation

    @State private var selectedSection: Section = .todos

    enum Section: String, CaseIterable, Identifiable {
        case todos = "Todo"
        case notes = "Notes"

        var id: String { rawValue }

        static func visible(noteCount: Int) -> [Section] {
            noteCount > 0 ? [.todos, .notes] : [.todos]
        }

        var icon: String {
            switch self {
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
                case .todos:
                    QuickCaptureView(
                        store: store,
                        captureState: captureState
                    )
                case .notes:
                    NotesListView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 620, minHeight: 440)
        .background(Color.narcBackground)
        .onChange(of: navigation.showTodosRequest) { _, _ in selectedSection = .todos }
        .onChange(of: store.notes.isEmpty) { _, isEmpty in
            if isEmpty { selectedSection = .todos }
        }
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
                selectedSection = .todos
            } label: {
                Label("新建 Todo", systemImage: "plus")
                    .font(.narcBody)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("打开 Todo")
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.vertical, NarcSpacing.lg)
    }

    private var sectionBar: some View {
        HStack(spacing: NarcSpacing.sm) {
            ForEach(Section.visible(noteCount: store.notes.count)) { section in
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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
        case .todos:
            return store.incompleteTodos.count
        case .notes:
            return store.notes.count
        }
    }
}
