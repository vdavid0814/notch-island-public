import SwiftUI

/// Siri AI's answer in the island, laid out as Siri lays it out: its text with the figures it
/// stresses in semibold and the things it links (tapped, Siri tells about them), the sources it
/// names, a picture, the files and apps it found (opened on a click), the photos, a message card
/// to write and send, and its buttons (Show More…). Each part is done in Siri AI
/// (`AssistantModel.performSiri`).
struct SiriAnswerView: View {
    let reply: SiriReply
    let isResponding: Bool

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reply.isEmpty, isResponding {
                Text("Siri is thinking…")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
            ForEach(Array(reply.blocks.enumerated()), id: \.offset) { _, block in
                part(block)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let title = SiriLink.title(in: url) else { return .systemAction }
            model.assistant.performSiri(.link(title))
            return .handled
        })
        .animation(.easeOut(duration: 0.2), value: reply)
    }

    @ViewBuilder private func part(_ block: SiriBlock) -> some View {
        switch block {
        case .paragraph(let runs, let heading):
            Text(SiriLink.text(runs))
                .font(.system(size: heading ? 17 : 15, weight: heading ? .semibold : .regular))
                .lineSpacing(2.5)
                .tint(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .sources(let names):
            HStack(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    Button(name) { model.assistant.performSiri(.button(name)) }
                        .buttonStyle(SiriChipStyle())
                }
            }
        case .image(let title):
            SiriPictureView(title: title)
        case .cards(let cards):
            VStack(spacing: 6) {
                ForEach(cards) { card in
                    SiriCardRow(card: card) { model.assistant.openSiriCard(card) }
                }
            }
        case .photos(let photos):
            SiriPhotoGrid(photos: photos)
        case .composer(let composer):
            SiriComposerCard(composer: composer)
        case .buttons(let names):
            HStack(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button { model.assistant.performSiri(.button(name)) } label: {
                        Text(name).frame(maxWidth: .infinity)
                    }
                    .islandButton(.capsule)
                    .controlSize(.regular)
                }
            }
        }
    }
}

/// Siri's links as links the island's text can be tapped on (`siri-link:?t=Moon`).
enum SiriLink {
    static func text(_ runs: [SiriRun]) -> AttributedString {
        var text = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            if run.bold { piece.font = .system(size: 15, weight: .semibold) }
            if run.link {
                var components = URLComponents()
                components.scheme = "siri-link"
                components.queryItems = [URLQueryItem(name: "t", value: run.text)]
                piece.link = components.url
                piece.underlineStyle = .single
            }
            text += piece
        }
        return text
    }

    static func title(in url: URL) -> String? {
        guard url.scheme == "siri-link" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "t" }?.value
    }
}

/// A source Siri names: small, grey, a capsule.
private struct SiriChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
            .contentShape(Capsule())
    }
}

/// A picture Siri shows of something, Wikipedia's for its title (`SiriPictures`); nothing when
/// there is none.
private struct SiriPictureView: View {
    let title: String
    @State private var image: NSImage?
    @State private var looked = false

    var body: some View {
        Group {
            if let image {
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if !looked {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .frame(height: 200)
            }
        }
        .task(id: title) {
            image = await SiriPictures.shared.picture(title)
            looked = true
        }
    }
}

/// A file or an app Siri found, as Siri shows it: its icon, name, the start of what it says, its
/// size.
private struct SiriCardRow: View {
    let card: SiriCard
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Group {
                    if let data = card.icon, let icon = NSImage(data: data) {
                        Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "doc.text").font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !card.detail.isEmpty {
                        Text(card.detail.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !card.size.isEmpty {
                        Text(card.size)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.white.opacity(isHovered ? 0.12 : 0.07), in: .rect(cornerRadius: 14, style: .continuous))
            .contentShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open")
    }
}

/// The photos Siri found, four to a row, from the library by the date Siri reads out; until the
/// library may be read, their places and a button that asks.
private struct SiriPhotoGrid: View {
    let photos: [SiriPhoto]
    @State private var allowed = SiriPictures.shared.photosAllowed

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                ForEach(photos.prefix(12)) { photo in
                    SiriPhotoCell(photo: photo, allowed: allowed)
                }
            }
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            if !allowed, SiriPictures.shared.photosUndecided {
                Button {
                    Task { allowed = await SiriPictures.shared.allowPhotos() }
                } label: {
                    Label("Show Photos Here", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .islandButton(.capsule)
            }
        }
    }
}

private struct SiriPhotoCell: View {
    let photo: SiriPhoto
    let allowed: Bool
    @State private var image: NSImage?

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: photo.isVideo ? "video" : "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay(alignment: .bottom) {
                HStack {
                    if photo.isFavourite { Image(systemName: "heart.fill") }
                    Spacer(minLength: 0)
                    if let duration = photo.duration { Text(duration) }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .padding(4)
            }
            .clipped()
            .contentShape(.rect)
            .onTapGesture { SiriPictures.shared.openPhotos() }
            .help(photo.label)
            .task(id: allowed) {
                guard allowed else { return }
                image = await SiriPictures.shared.photo(photo, side: 120)
            }
    }
}

/// Siri's message card: who to, a field for the text, and Siri's buttons (Cancel, Send), done in
/// Siri AI.
private struct SiriComposerCard: View {
    let composer: SiriComposer
    @State private var text = ""
    @Environment(AppModel.self) private var model

    var body: some View {
        let parts = composer.recipient.components(separatedBy: ", ")
        let send = composer.actions.last
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(parts.first ?? composer.recipient)
                        .font(.system(size: 14, weight: .semibold))
                    if parts.count > 1 {
                        Text(parts.dropFirst().joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Message", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
                .onSubmit { if let send, !text.isEmpty { model.assistant.sendSiriMessage(text, with: send) } }
            HStack(spacing: 8) {
                ForEach(composer.actions, id: \.self) { title in
                    Button {
                        if title == send { model.assistant.sendSiriMessage(text, with: title) } else { model.assistant.performSiri(.button(title)) }
                    } label: {
                        Text(title).frame(maxWidth: .infinity)
                    }
                    .islandButton(.capsule, prominent: title == send)
                    .controlSize(.regular)
                    .disabled(title == send && text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 16, style: .continuous))
        .onAppear { text = composer.text }
    }
}
