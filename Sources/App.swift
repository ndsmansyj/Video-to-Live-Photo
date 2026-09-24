import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var library = LiveLibrary()
    @State private var page: AppPage

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--ui-page"),
           arguments.indices.contains(flagIndex + 1),
           let requestedPage = AppPage(rawValue: arguments[flagIndex + 1]) {
            _page = State(initialValue: requestedPage)
        } else {
            _page = State(initialValue: .recent)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(library: library, page: $page)
            Divider()

            Group {
                switch page {
                case .recent:
                    RecentView(library: library)
                case .history:
                    HistoryView(library: library)
                case .settings:
                    SettingsView(library: library)
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.30))
        }
        .frame(minWidth: 1040, minHeight: 720)
        .animation(.easeInOut(duration: 0.15), value: page)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}

@main
struct SPPLiveExportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
