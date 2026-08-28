import SwiftUI

@main
struct IntuneSDKTestApp: App {
    @StateObject private var notesStore = NotesStore()
    @StateObject private var authService = AuthenticationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(notesStore)
                .environmentObject(authService)
        }
    }
}
