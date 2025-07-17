import SwiftUI

@main
struct MOSSUApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var slackManager = SlackStatusManager()

    init() {
        appDelegate.slackManager = slackManager
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(slackManager: slackManager, delegate: appDelegate)
        } label: {
            if let office = slackManager.currentOffice {
                Image(nsImage: office.barIconImage)
            } else {
                Image("AppIcon")
            }
        }
        Settings {
            EmptyView()
        }
    }
}
