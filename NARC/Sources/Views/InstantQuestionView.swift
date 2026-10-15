import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

final class InstantQuestionModeSelection: ObservableObject {
    @Published var mode: InstantQuestionView.Mode
    @Published private(set) var inputFocusRequest = UUID()

    func requestInputFocus() { inputFocusRequest = UUID() }

    init(_ mode: InstantQuestionView.Mode = .ask) {
        self.mode = mode
    }
}

struct InstantQuestionView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case ask = "问 DeepSeek"
        case bing = "Bing 搜索"
        case google = "Google 搜索"
        var id: String { rawValue }
        var showsSavedQuestions: Bool { self == .ask }
        var toolbarActionTitle: String { self == .ask ? "清空当前" : "刷新" }
        var toolbarActionSystemImage: String { self == .ask ? "arrow.counterclockwise" : "arrow.clockwise" }
        var toolbarActionHelp: String {
            self == .ask ? "清空当前整段问答，不影响已保存内容" : "刷新当前 \(self == .bing ? "Bing" : "Google") 页面"
        }
    }

    @ObservedObject var controller: InstantQuestionController
    @ObservedObject var store: InstantQuestionStore
    @ObservedObject private var credentials: InstantQuestionCredentialManager
    let onOpenPreferences: () -> Void

    @StateObject private var modeSelection: InstantQuestionModeSelection
    @State private var expandedRecordID: UUID?
    @State private var isShowingSaved = false
    @State private var bingRefreshToken = UUID()
    @State private var bingQuery = ""
    @State private var googleQuery = ""
    @State private var bingPageURL = WebSearchProvider.bing.homeURL
    @State private var googlePageURL = WebSearchProvider.google.homeURL
    @State private var attachmentThumbnail: NSImage?
    @State private var isShowingImagePreview = false

    init(
        controller: InstantQuestionController,
        store: InstantQuestionStore,
        onOpenPreferences: @escaping () -> Void,
        initialMode: Mode = .ask,
        modeSelection: InstantQuestionModeSelection? = nil
    ) {
        self.controller = controller
        self.store = store
        self.onOpenPreferences = onOpenPreferences
        _credentials = ObservedObject(wrappedValue: controller.credentials)
        _modeSelection = StateObject(
            wrappedValue: modeSelection ?? InstantQuestionModeSelection(initialMode)
        )
    }

    var body: some View {
        VStack(spacing: NarcSpacing.md) {
            HStack(spacing: NarcSpacing.sm) {
                Picker("搜索方式", selection: $modeSelection.mode) {
                    ForEach(Mode.allCases) { selectedMode in
                        Text(selectedMode.rawValue)
                            .lineLimit(1)
                            .tag(selectedMode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440)

                Spacer(minLength: 0)

                if mode.showsSavedQuestions {
                    Button {
                        isShowingSaved = true
                    } label: {
                        Label("已保存问答", systemImage: "tray.full")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.borderless)
                    .help("查看已保存的完整对话")
                    .accessibilityLabel("查看已保存问答，共 \(store.records.count) 条")
                }

                Button(action: performToolbarAction) {
                    Label(mode.toolbarActionTitle, systemImage: mode.toolbarActionSystemImage)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.borderless)
                .disabled(mode == .ask && !hasCurrentQuestionContent)
                .help(mode.toolbarActionHelp)
            }
            .padding(.top, NarcSpacing.lg)

            if mode == .ask {
                askView
            } else if mode == .bing {
                WebSearchView(provider: .bing, refreshToken: bingRefreshToken,
                              query: $bingQuery, pageURL: $bingPageURL)
                    .id(mode)
            } else {
                WebSearchView(provider: .google, refreshToken: bingRefreshToken,
                              query: $googleQuery, pageURL: $googlePageURL)
                    .id(mode)
            }
        }
        .padding(.horizontal, NarcSpacing.xl)
        .padding(.bottom, NarcSpacing.xl)
        .background(Color.narcBackground)
        .onChange(of: modeSelection.mode) { _, mode in
            if mode == .ask { modeSelection.requestInputFocus() }
        }
        .onChange(of: controller.imageAttachment, initial: true) { _, attachment in
            attachmentThumbnail = attachment.flatMap {
                InstantQuestionImagePresentation.image(data: $0.data, maximumPixelSize: 120)
            }
            if attachment == nil { isShowingImagePreview = false }
        }
        .sheet(isPresented: $isShowingImagePreview, onDismiss: modeSelection.requestInputFocus) {
            if let attachment = controller.imageAttachment {
                InstantQuestionAttachmentPreview(attachment: attachment)
            }
        }
        .sheet(isPresented: $isShowingSaved, onDismiss: modeSelection.requestInputFocus) {
            VStack(spacing: 0) {
                HStack {
                    Text("已保存问答")
                        .font(.narcTitle)
                    Spacer()
                    Button("完成") { isShowingSaved = false }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(NarcSpacing.xl)
                Divider()
                savedView.padding(NarcSpacing.xl)
            }
            .frame(minWidth: 560, minHeight: 420)
            .background(Color.narcBackground)
        }
    }

    private var mode: Mode { modeSelection.mode }

    private var askView: some View {
        VStack(spacing: NarcSpacing.md) {
            if !credentials.isReady {
                configurationBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: NarcSpacing.md) {
                        if controller.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(controller.messages) { message in
                                VStack(alignment: .leading, spacing: NarcSpacing.sm) {
                                    messageBubble(message)
                                    if message.role == .assistant {
                                        let messageSources = sources(
                                            with: message.sourceIDs,
                                            from: controller.sources
                                        )
                                        if !messageSources.isEmpty { sourcesCard(messageSources) }
                                    }
                                }
                                .id(message.id)
                            }
                            if !controller.streamingAnswer.isEmpty {
                                messageBubble(content: controller.streamingAnswer, role: .assistant)
                                    .id("streaming-answer")
                            }
                            if controller.isBusy {
                                progressRow
                            }
                            if let error = controller.errorMessage {
                                errorCard(error)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, NarcSpacing.sm)
                }
                .onChange(of: controller.messages.count) { _, _ in
                    if let last = controller.messages.last {
                        withAnimation(.narcSnap) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: controller.streamingAnswer) { _, answer in
                    if !answer.isEmpty { proxy.scrollTo("streaming-answer", anchor: .bottom) }
                }
            }

            if controller.canSave {
                answerActions
            }
            composer
        }
    }

    private var configurationBanner: some View {
        HStack(spacing: NarcSpacing.md) {
            Image(systemName: "key.horizontal")
                .foregroundStyle(Color.narcWarn)
            VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                Text(credentials.hasDeepSeekKey ? "请先在设置中授权读取密钥" : "配置 DeepSeek API Key 后即可提问")
                    .font(.narcBody)
                    .foregroundStyle(Color.narcText)
                Text("在“即时问答”设置中完成配置和授权；Bing / Google 不受影响。")
                    .font(.narcCaption)
                    .foregroundStyle(Color.narcTextMuted)
            }
            Spacer(minLength: NarcSpacing.sm)
            Button("打开设置", action: onOpenPreferences)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(NarcSpacing.md)
        .background(Color.narcFocusInset)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            Label("直接问，也可以添加截图", systemImage: "sparkles")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            Text("DeepSeek 负责文字和图片理解，不会读取 Bing 搜索结果。只有你点击保存，问答文字才会写入本地。")
                .font(.narcBody)
                .foregroundStyle(Color.narcTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            Label("图片只用于当前会话，保存问答时不落盘原图", systemImage: "photo")
                .font(.narcCaption)
                .foregroundStyle(Color.narcInfo)
        }
        .padding(NarcSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.narcFocusSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.focus, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.focus, style: .continuous)
                .stroke(Color.narcBorder, lineWidth: 1)
        )
    }

    private func messageBubble(_ message: InstantQuestionMessage) -> some View {
        messageBubble(content: message.content, role: message.role)
    }

    private func messageBubble(content: String, role: InstantQuestionRole) -> some View {
        HStack {
            if role == .user { Spacer(minLength: 72) }
            Group {
                if role == .assistant {
                    InstantQuestionMarkdownView(content: content)
                } else {
                    Text(content)
                }
            }
                .font(.narcBody)
                .foregroundStyle(Color.narcText)
                .textSelection(.enabled)
                .padding(NarcSpacing.md)
                .background(role == .user ? Color.narcAccent.opacity(0.13) : Color.narcFocusSurface)
                .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                        .stroke(Color.narcBorder.opacity(role == .user ? 0 : 1), lineWidth: 1)
                )
            if role == .assistant { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity)
    }

    private var progressRow: some View {
        HStack(spacing: NarcSpacing.sm) {
            ProgressView().controlSize(.small)
            Text(controller.imageAttachment == nil ? "DeepSeek 正在回答…" : "正在上传图片并识别…")
                .font(.narcCaption)
                .foregroundStyle(Color.narcTextMuted)
        }
        .padding(.horizontal, NarcSpacing.sm)
    }

    private func sourcesCard(_ sources: [InstantQuestionSource]) -> some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            Label("历史来源", systemImage: "link")
                .font(.narcSubtitle)
                .foregroundStyle(Color.narcText)
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                Link(destination: source.url) {
                    HStack(alignment: .firstTextBaseline, spacing: NarcSpacing.sm) {
                        Text("[\(index + 1)]")
                            .font(.narcMonoSmall)
                            .foregroundStyle(Color.narcAccent)
                        Text(source.title.isEmpty ? source.url.host ?? source.url.absoluteString : source.title)
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcTextMuted)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.narcCaption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(NarcSpacing.md)
        .background(Color.narcFocusInset)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.narcCaption)
            .foregroundStyle(Color.narcDanger)
            .padding(NarcSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.narcDanger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm, style: .continuous))
    }

    private var answerActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NarcSpacing.sm) {
                actionButton(
                    controller.savedRecordID == nil ? "保存本次对话" : "更新已保存对话",
                    icon: "bookmark",
                    action: { _ = controller.saveCurrent() }
                )
                    .buttonStyle(NarcFocusPrimaryButtonStyle())
                actionButton(
                    "复制本轮回答",
                    icon: "doc.on.doc",
                    action: controller.copyLatestAnswer
                )
                Spacer()
                if controller.savedRecordID != nil {
                    Label("已保存", systemImage: "checkmark.circle.fill")
                        .font(.narcCaption)
                        .foregroundStyle(Color.narcSuccess)
                        .lineLimit(1)
                }
            }
            HStack(spacing: NarcSpacing.sm) {
                iconAction(
                    controller.savedRecordID == nil ? "保存本次对话" : "更新已保存对话",
                    icon: "bookmark",
                    action: { _ = controller.saveCurrent() }
                )
                    .buttonStyle(NarcFocusPrimaryButtonStyle())
                iconAction("复制本轮回答", icon: "doc.on.doc", action: controller.copyLatestAnswer)
                Spacer()
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            if let attachment = controller.imageAttachment {
                HStack(spacing: NarcSpacing.sm) {
                    Button { isShowingImagePreview = true } label: {
                        Group {
                            if let attachmentThumbnail {
                                Image(nsImage: attachmentThumbnail).resizable().scaledToFit()
                            } else {
                                Image(systemName: "photo").foregroundStyle(Color.narcAccent)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .background(Color.narcFocusInset)
                        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(attachmentThumbnail == nil)
                    .help("点击查看图片")
                    .accessibilityLabel("查看图片：\(attachment.name)")
                    VStack(alignment: .leading, spacing: NarcSpacing.xxs) {
                        Text(attachment.name).foregroundStyle(Color.narcText).lineLimit(1)
                        Text("点击缩略图预览 · 不会随问答保存")
                            .foregroundStyle(Color.narcTextFaint).lineLimit(1)
                    }
                    .font(.narcCaption)
                    Spacer(minLength: 0)
                    Button(action: controller.removeImage) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("移除图片")
                    .accessibilityLabel("移除图片")
                }
                .padding(.horizontal, NarcSpacing.sm)
            }

            VStack(spacing: 0) {
                InstantQuestionTextEditor(
                    text: $controller.draft,
                    placeholder: controller.imageAttachment == nil
                        ? "问一个问题…"
                        : "针对这张图片提问…",
                    isEnabled: !controller.isBusy,
                    focusRequest: modeSelection.inputFocusRequest,
                    onPasteImage: pasteImage(from:)
                )
                    .frame(minHeight: 54, maxHeight: 96)
                    .accessibilityLabel("输入即时问题")

                HStack(spacing: NarcSpacing.sm) {
                    attachmentMenu
                    Spacer(minLength: 0)
                    Button(action: controller.sendDraft) {
                        Label("发送", systemImage: "arrow.up")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(NarcFocusPrimaryButtonStyle())
                    .disabled(!controller.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .background(Color.narcFocusSurface)
            .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .stroke(Color.narcBorder, lineWidth: 1))
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button("从剪贴板添加", systemImage: "doc.on.clipboard", action: attachImageFromPasteboard)
            Button("选择图片…", systemImage: "folder", action: chooseImage)
        } label: {
            Image(systemName: "paperclip")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(controller.isBusy)
        .help("添加图片")
        .accessibilityLabel("添加图片")
    }

    private var savedView: some View {
        ScrollView {
            LazyVStack(spacing: NarcSpacing.sm) {
                if store.records.isEmpty {
                    ContentUnavailableView(
                        "还没有保存的问答",
                        systemImage: "bookmark",
                        description: Text("DeepSeek 问答默认不留记录，只有主动保存后才会出现在这里。")
                    )
                    .frame(minHeight: 260)
                } else {
                    ForEach(store.records) { record in savedRecord(record) }
                }
            }
            .padding(.top, NarcSpacing.sm)
        }
    }

    private func savedRecord(_ record: SavedInstantQuestion) -> some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            HStack(spacing: NarcSpacing.sm) {
                Button {
                    withAnimation(.narcSnap) {
                        expandedRecordID = expandedRecordID == record.id ? nil : record.id
                    }
                } label: {
                    HStack(spacing: NarcSpacing.sm) {
                        Image(systemName: expandedRecordID == record.id ? "chevron.down" : "chevron.right")
                        Text(record.title)
                            .font(.narcBody)
                            .foregroundStyle(Color.narcText)
                            .lineLimit(1)
                        Spacer()
                        Text(record.updatedAt, style: .date)
                            .font(.narcCaption)
                            .foregroundStyle(Color.narcTextFaint)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                Button { _ = store.delete(id: record.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除这条已保存问答")
                .accessibilityLabel("删除已保存问答")
            }

            if expandedRecordID == record.id {
                ForEach(record.messages) { message in
                    Text(message.content)
                        .font(.narcCaption)
                        .foregroundStyle(message.role == .user ? Color.narcText : Color.narcTextMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if message.role == .assistant {
                        let messageSources = sources(with: message.sourceIDs, from: record.sources)
                        if !messageSources.isEmpty { sourcesCard(messageSources) }
                    }
                }
            }
        }
        .padding(NarcSpacing.md)
        .background(Color.narcFocusSurface)
        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NarcRadius.md, style: .continuous)
                .stroke(Color.narcBorder, lineWidth: 1)
        )
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func iconAction(_ help: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .help(help)
            .accessibilityLabel(help)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择要交给 DeepSeek 识别的图片"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let attachment = try InstantQuestionImageInput.attachment(from: url)
                try attach(attachment)
            } catch {
                controller.report(error)
            }
        }
    }

    private func attachImageFromPasteboard() {
        do {
            guard let attachment = try InstantQuestionImageInput.attachment(from: .general) else {
                throw InstantQuestionController.AttachmentFailure.empty
            }
            try attach(attachment)
        } catch {
            controller.report(error)
        }
    }

    private func pasteImage(from pasteboard: NSPasteboard) -> Bool {
        do {
            guard let attachment = try InstantQuestionImageInput.attachment(from: pasteboard) else {
                return false
            }
            try attach(attachment)
            return true
        } catch {
            controller.report(error)
            return true
        }
    }

    private func attach(_ attachment: InstantQuestionImageAttachment) throws {
        try controller.attachImage(
            name: attachment.name,
            mediaType: attachment.mediaType,
            data: attachment.data
        )
        modeSelection.requestInputFocus()
    }

    private var hasCurrentQuestionContent: Bool {
        controller.isBusy
            || !controller.draft.isEmpty
            || !controller.messages.isEmpty
            || controller.imageAttachment != nil
            || controller.errorMessage != nil
    }

    private func performToolbarAction() {
        switch mode {
        case .ask:
            controller.clearCurrent()
        case .bing, .google:
            bingRefreshToken = UUID()
        }
    }

    private func sources(
        with ids: [UUID],
        from allSources: [InstantQuestionSource]
    ) -> [InstantQuestionSource] {
        let sourcesByID = Dictionary(uniqueKeysWithValues: allSources.map { ($0.id, $0) })
        return ids.compactMap { sourcesByID[$0] }
    }
}

/// Decode a bounded display image without altering the attachment sent to AI.
/// Thumbnails are cached in view state, not decoded on each streaming update.
enum InstantQuestionImagePresentation {
    static func image(data: Data, maximumPixelSize: Int) -> NSImage? {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(2048, maximumPixelSize),
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }
}

struct InstantQuestionAttachmentPreview: View {
    let attachment: InstantQuestionImageAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var displayImage: NSImage?

    var body: some View {
        VStack(spacing: NarcSpacing.md) {
            HStack {
                Text(attachment.name).font(.narcSubtitle).lineLimit(1)
                Spacer(minLength: NarcSpacing.sm)
                Button("完成") { dismiss() }
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .keyboardShortcut(.cancelAction)
            }
            if let displayImage {
                Image(nsImage: displayImage).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("图片预览：\(attachment.name)")
            } else {
                ContentUnavailableView("无法预览这张图片", systemImage: "photo")
            }
            Text("仅预览当前图片，不会保存或发送新请求。")
                .font(.narcCaption).foregroundStyle(Color.narcTextMuted)
        }
        .padding(NarcSpacing.xl)
        .frame(width: 640, height: 480)
        .background(Color.narcBackground)
        .onAppear {
            displayImage = InstantQuestionImagePresentation.image(data: attachment.data, maximumPixelSize: 1800)
        }
    }
}

enum InstantQuestionMarkdown {
    enum Block: Equatable {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String)
        case numbered(String, String)
        case quote(String)
        case code(String)
    }

    static func blocks(_ source: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func finishParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if code != nil {
                if rawLine.hasPrefix("```") {
                    result.append(.code(code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(rawLine)
                }
                continue
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                finishParagraph()
                code = []
            } else if line.isEmpty {
                finishParagraph()
            } else if let heading = heading(in: line) {
                finishParagraph()
                result.append(heading)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                finishParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else if let numbered = numberedItem(in: line) {
                finishParagraph()
                result.append(numbered)
            } else if line.hasPrefix("> ") {
                finishParagraph()
                result.append(.quote(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        if let code { result.append(.code(code.joined(separator: "\n"))) }
        finishParagraph()
        return result
    }

    static func attributed(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

    private static func heading(in line: String) -> Block? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(count), line.dropFirst(count).first == " " else { return nil }
        return .heading(count, String(line.dropFirst(count + 1)))
    }

    private static func numberedItem(in line: String) -> Block? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3,
              let marker = line.dropFirst(digits.count).first,
              marker == "." || marker == ")",
              line.dropFirst(digits.count + 1).first == " " else { return nil }
        return .numbered(String(digits) + String(marker), String(line.dropFirst(digits.count + 2)))
    }
}

private struct InstantQuestionMarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: NarcSpacing.sm) {
            ForEach(Array(InstantQuestionMarkdown.blocks(content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(InstantQuestionMarkdown.attributed(text))
                case .heading(let level, let text):
                    Text(InstantQuestionMarkdown.attributed(text))
                        .font(level == 1 ? .narcTitle : .narcSubtitle)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: NarcSpacing.sm) {
                        Text("•")
                        Text(InstantQuestionMarkdown.attributed(text))
                    }
                case .numbered(let marker, let text):
                    HStack(alignment: .firstTextBaseline, spacing: NarcSpacing.sm) {
                        Text(marker)
                        Text(InstantQuestionMarkdown.attributed(text))
                    }
                case .quote(let text):
                    HStack(spacing: NarcSpacing.sm) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.narcAccent.opacity(0.45))
                            .frame(width: 3)
                        Text(InstantQuestionMarkdown.attributed(text))
                    }
                case .code(let text):
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(NarcSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.narcFocusInset)
                        .clipShape(RoundedRectangle(cornerRadius: NarcRadius.sm))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Native editor keeps the insertion caret and placeholder on the same text inset,
/// and lets image data pasted into the field become the current visual attachment.
private struct InstantQuestionTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let focusRequest: UUID
    let onPasteImage: (NSPasteboard) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = InstantQuestionPasteAwareTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.onPasteImage = onPasteImage
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InstantQuestionPasteAwareTextView else { return }
        context.coordinator.parent = self
        if textView.string != text { textView.string = text }
        textView.placeholder = placeholder
        textView.onPasteImage = onPasteImage
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled
        textView.requestInputFocus(focusRequest)
        textView.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InstantQuestionTextEditor

        init(parent: InstantQuestionTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            textView.needsDisplay = true
        }
    }
}

final class InstantQuestionPasteAwareTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var onPasteImage: ((NSPasteboard) -> Bool)?
    var imagePasteboard: () -> NSPasteboard = { .general }
    private var pendingFocusRequest: UUID?
    private var completedFocusRequest: UUID?
    private var keyWindowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
        if let window {
            keyWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.fulfillInputFocus() }
            }
        }
        scheduleInputFocus()
    }

    deinit {
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
    }

    func requestInputFocus(_ id: UUID) {
        guard completedFocusRequest != id else { return }
        pendingFocusRequest = id
        scheduleInputFocus()
    }

    private func scheduleInputFocus() {
        DispatchQueue.main.async { [weak self] in self?.fulfillInputFocus() }
    }

    private func fulfillInputFocus() {
        guard let pendingFocusRequest, pendingFocusRequest != completedFocusRequest,
              isEditable, let window, window.isVisible,
              window.attachedSheet == nil else { return }
        // Prepare the window-local responder even while app activation is
        // finishing. makeFirstResponder does not activate another window/app;
        // requiring isKeyWindow here can miss the initial activation handoff.
        if window.makeFirstResponder(self) {
            completedFocusRequest = pendingFocusRequest
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)), isEditable,
           InstantQuestionImageInput.canPasteImage(from: imagePasteboard()) {
            return true
        }
        return super.validateMenuItem(menuItem)
    }

    override func paste(_ sender: Any?) {
        if pasteImageIfAvailable(from: imagePasteboard()) { return }
        super.paste(sender)
    }

    @discardableResult
    func pasteImageIfAvailable(from pasteboard: NSPasteboard) -> Bool {
        onPasteImage?(pasteboard) == true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let font = font ?? NSFont.systemFont(ofSize: 13)
        let rect = NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height,
            width: max(0, bounds.width - textContainerInset.width * 2),
            height: ceil(font.boundingRectForFont.height)
        )
        (placeholder as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
    }
}

enum InstantQuestionImageInput {
    private static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    private static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
    private static let webPType = NSPasteboard.PasteboardType("org.webmproject.webp")
    private static let directTypes: [(NSPasteboard.PasteboardType, String, String)] = [
        (.png, "剪贴板图片.png", "image/png"),
        (jpegType, "剪贴板图片.jpg", "image/jpeg"),
        (gifType, "剪贴板图片.gif", "image/gif"),
        (webPType, "剪贴板图片.webp", "image/webp"),
    ]

    static func canPasteImage(from pasteboard: NSPasteboard) -> Bool {
        if pasteboard.availableType(from: directTypes.map { $0.0 } + [.tiff]) != nil {
            return true
        }
        guard let fileURL = pasteboard.string(forType: .fileURL),
              let url = URL(string: fileURL), url.isFileURL else { return false }
        return ["jpg", "jpeg", "png", "gif", "webp"].contains(url.pathExtension.lowercased())
    }

    static func attachment(from pasteboard: NSPasteboard) throws -> InstantQuestionImageAttachment? {
        for (type, name, mediaType) in directTypes {
            if let data = pasteboard.data(forType: type) {
                return InstantQuestionImageAttachment(name: name, mediaType: mediaType, data: data)
            }
        }
        if let data = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return InstantQuestionImageAttachment(
                name: "剪贴板图片.png",
                mediaType: "image/png",
                data: png
            )
        }
        if let fileURL = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileURL), url.isFileURL {
            return try attachment(from: url)
        }
        return nil
    }

    static func attachment(from url: URL) throws -> InstantQuestionImageAttachment {
        let mediaType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": mediaType = "image/jpeg"
        case "png": mediaType = "image/png"
        case "gif": mediaType = "image/gif"
        case "webp": mediaType = "image/webp"
        default: throw InstantQuestionController.AttachmentFailure.unsupportedFormat
        }
        if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > InstantQuestionImageAttachment.maximumByteCount {
            throw InstantQuestionController.AttachmentFailure.tooLarge
        }
        return InstantQuestionImageAttachment(
            name: url.lastPathComponent,
            mediaType: mediaType,
            data: try Data(contentsOf: url, options: .mappedIfSafe)
        )
    }
}
