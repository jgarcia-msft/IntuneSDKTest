import SwiftUI

struct RootView: View {
    @EnvironmentObject private var notesStore: NotesStore
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        Group {
            switch authService.state {
            case .signedOut, .failed:
                SignInView()
            case .signingIn:
                ProgressView("Signing in with Microsoft...")
            case let .signedIn(username, accountID):
                NotesHomeView(username: username, accountID: accountID)
            }
        }
        .onAppear {
            authService.showLaunchDiagnosticsIfEnabled()
        }
    }
}

private struct SignInView: View {
    @EnvironmentObject private var authService: AuthenticationService

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text("IntuneSDKTest")
                .font(.largeTitle.bold())
            Text("A small Notes-style app for learning MSAL and Intune App SDK integration.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if case let .failed(message) = authService.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button(action: authService.signIn) {
                Label("Sign in with Microsoft", systemImage: "person.badge.key")
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }
}

private struct NotesHomeView: View {
    @EnvironmentObject private var notesStore: NotesStore
    @EnvironmentObject private var authService: AuthenticationService

    let username: String
    let accountID: String
    @State private var navigationPath: [UUID] = []
    @State private var showingAccount = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(notesStore.notes) { note in
                    NavigationLink(value: note.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.headline)
                                .lineLimit(1)
                            HStack {
                                Text(note.updatedAt, style: .date)
                                Text(note.body.isEmpty ? "No text" : note.body)
                                    .lineLimit(1)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: notesStore.delete)
            }
            .overlay {
                if notesStore.notes.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "note.text")
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: UUID.self) { noteID in
                NoteEditorView(noteID: noteID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Account", systemImage: "person.crop.circle") {
                        showingAccount = true
                    }
                    .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New note", systemImage: "square.and.pencil") {
                        navigationPath.append(notesStore.addNote().id)
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $showingAccount) {
                AccountView(username: username, accountID: accountID)
            }
        }
    }
}

private struct NoteEditorView: View {
    @EnvironmentObject private var notesStore: NotesStore
    let noteID: UUID
    @State private var title = ""
    @State private var bodyText = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.title2.bold())
                .padding()
            TextEditor(text: $bodyText)
                .padding(.horizontal, 12)
                .scrollContentBackground(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let note = notesStore.notes.first(where: { $0.id == noteID }) else { return }
            title = note.title
            bodyText = note.body
        }
        .onChange(of: title) { save() }
        .onChange(of: bodyText) { save() }
    }

    private func save() {
        guard var note = notesStore.notes.first(where: { $0.id == noteID }) else { return }
        note.title = title
        note.body = bodyText
        notesStore.update(note)
    }
}

private struct AccountView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @EnvironmentObject private var notesStore: NotesStore
    @Environment(\.dismiss) private var dismiss

    let username: String
    let accountID: String

    var body: some View {
        NavigationStack {
            Form {
                Section("MSAL account") {
                    LabeledContent("User", value: username)
                    LabeledContent("Entra object ID", value: accountID)
                }
                Section("Intune MAM") {
                    LabeledContent("Enrollment") {
                        Label(
                            authService.enrollmentID == nil ? "Pending" : "Enrolled",
                            systemImage: authService.enrollmentID == nil ? "clock" : "checkmark.shield"
                        )
                        .foregroundStyle(authService.enrollmentID == nil ? .orange : .green)
                    }
                    Button("Refresh enrollment", systemImage: "arrow.clockwise") {
                        authService.refreshEnrollment()
                    }
                    Button("Open diagnostic console", systemImage: "ladybug") {
                        authService.showIntuneDiagnosticConsole()
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        dismiss()
                        authService.signOut(deleteLocalData: notesStore.deleteAll)
                    }
                } footer: {
                    Text("The app unregisters this identity from Intune and wipes local notes before MSAL signs out.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: authService.refreshEnrollment)
        }
    }
}