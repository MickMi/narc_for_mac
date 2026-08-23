import SwiftUI

struct NotesListView: View {
    @ObservedObject var store: AssistantStore
    let onCreate: () -> Void

    @State private var query = ""
    @State private var pendingDeletion: NoteItem?

    private var filteredNotes: [NoteItem] {
        store.searchNotes(query: query)
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if let error = store.lastError?.errorDescription {
                errorBanner(error)
            }

            if store.notes.isEmpty {
                emptyState
            } else if filteredNotes.isEmpty {
                noResultsState
            } else {
                noteList
            }
        }
        .background(Color.narcBackground)
        .alert("删除这条 Note？", isPresented: deletionConfirmation) {
            Button("删除", role: .destructive) {
                if let pendingDeletion {
                    _ = store.deleteNote(id: pendingDeletion.id)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("删除后将从本机数据中移除，当前版本不提供撤销。")
        }
    }

    private var searchBar: some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.narcTextMuted)

            TextField("搜索 Notes", text: $query)
                .textFieldStyle(.plain)
                .font(.narcBody)
                .accessibilityLabel("搜索 Notes")

            if hasQuery {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.narcTextMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除 Note 搜索")
            }
        }
        .padding(.horizontal, NarcSpacing.md)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous)
                .strokeBorder(Color.narcBorder, lineWidth: 0.5)
        )
        .padding(NarcSpacing.lg)
        .padding(.bottom, 0)
    }

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: NarcSpacing.sm) {
                ForEach(filteredNotes) { note in
                    NoteItemRow(note: note) {
                        pendingDeletion = note
                    }
                }
            }
            .padding(NarcSpacing.lg)
        }
    }

    private var emptyState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 34))
                .foregroundColor(.narcTextMuted)
            Text("还没有 Note")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)
            Text("快速保存一段想法、决定或备忘。")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
            Button("新建 Note", action: onCreate)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("新建 Note")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: NarcSpacing.md) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(.narcTextMuted)
            Text("没有匹配的 Note")
                .font(.narcSubtitle)
                .foregroundColor(.narcText)
            Text("换一个关键词，或清除当前搜索。")
                .font(.narcCaption)
                .foregroundColor(.narcTextMuted)
            Button("清除搜索") {
                query = ""
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deletionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: NarcSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.narcCaption)
        .foregroundColor(.narcDanger)
        .padding(.horizontal, NarcSpacing.lg)
        .padding(.vertical, NarcSpacing.sm)
        .background(Color.narcDanger.opacity(0.08))
        .accessibilityLabel("Note 保存错误：\(message)")
    }
}

private struct NoteItemRow: View {
    let note: NoteItem
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: NarcSpacing.md) {
            Image(systemName: "note.text")
                .font(.narcSubtitle)
                .foregroundColor(.narcAccent)

            VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                Text(note.content)
                    .font(.narcBody)
                    .foregroundColor(.narcText)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(note.updatedAt, style: .relative)
                    .font(.narcCaption)
                    .foregroundColor(.narcTextFaint)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.narcCaption)
                    .foregroundColor(.narcTextMuted)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.65)
            .accessibilityLabel("删除 Note")
        }
        .padding(NarcSpacing.md)
        .softRowBackground(
            isSelected: false,
            needsAttention: false,
            isHovering: isHovering
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
