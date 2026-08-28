import Combine
import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "", body: String = "", updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    private let storageURL: URL

    init(fileManager: FileManager = .default) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IntuneSDKTest", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("notes.json")
        load()
    }

    func addNote() -> Note {
        let note = Note(title: "New note")
        notes.insert(note, at: 0)
        save()
        return note
    }

    func update(_ note: Note) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updatedNote = note
        updatedNote.updatedAt = .now
        notes[index] = updatedNote
        notes.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            notes.remove(at: index)
        }
        save()
    }

    // Intune can encrypt this file and enforce file-protection policy. Keeping the
    // app's persistence in one file also makes selective wipe behavior easy to test.
    func deleteAll() {
        notes.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let savedNotes = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = savedNotes.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        // The iOS protection class protects the local copy even before an Intune
        // policy is applied; Intune can add its own MAM encryption and restrictions.
        try? data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
