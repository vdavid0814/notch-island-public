import Foundation

/// What one widget instance keeps that is too large for the board's JSON (`WidgetConfig`): a photo
/// frame's picture, as a copy of its own so it survives the original moving. One folder per
/// widget under `Application Support/NotchIsland/Widgets/<id>/`, removed with the widget; folders
/// whose widget is gone (a reset, a board edited by hand) are removed after launch.
///
/// Every call touches the disk: never on the main thread.
nonisolated struct WidgetInstanceStore: Sendable {
    let root: URL

    static let standard = WidgetInstanceStore(
        root: (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
               ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("NotchIsland", isDirectory: true)
            .appendingPathComponent("Widgets", isDirectory: true)
    )

    func folder(for id: WidgetID) -> URL { root.appendingPathComponent(id.description, isDirectory: true) }

    /// Where `name` is kept for the widget (the folder is made on the first write).
    func url(_ name: String, for id: WidgetID) -> URL { folder(for: id).appendingPathComponent(name) }

    func write(_ data: Data, _ name: String, for id: WidgetID) throws {
        try FileManager.default.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        try data.write(to: url(name, for: id), options: .atomic)
    }

    func read(_ name: String, for id: WidgetID) -> Data? { try? Data(contentsOf: url(name, for: id)) }

    /// Copies the widget's files to another widget's folder (a duplicate keeps its own copy).
    func copy(from source: WidgetID, to destination: WidgetID) {
        let from = folder(for: source)
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: from, to: folder(for: destination))
    }

    func purge(_ id: WidgetID) { try? FileManager.default.removeItem(at: folder(for: id)) }

    /// Removes every folder whose widget is not among `ids`. Folders not named like an id are left.
    func purge(keeping ids: Set<WidgetID>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            guard let id = WidgetID(string: name), !ids.contains(id) else { continue }
            purge(id)
        }
    }
}
