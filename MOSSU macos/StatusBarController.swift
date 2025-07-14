import Cocoa

class StatusBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: 18)
        statusItem.button?.title = ""
        statusItem.button?.image = NSImage(named: "AppIcon")
        statusItem.button?.image?.size = NSSize(width: 28, height: 28)
    }

    func update(validToken: Bool,
                text: String?,
                office: Office?,
                lastUpdate: Date?,
                name: String,
                paused: Bool,
                holidayEndDate: Date?,
                authSelector: Selector,
                pauseSelector: Selector,
                holidaySelector: Selector,
                updateSelector: Selector) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.configureMenus(validToken: validToken,
                                  text: text,
                                  office: office,
                                  lastUpdate: lastUpdate,
                                  name: name,
                                  paused: paused,
                                  holidayEndDate: holidayEndDate,
                                  authSelector: authSelector,
                                  pauseSelector: pauseSelector,
                                  holidaySelector: holidaySelector,
                                  updateSelector: updateSelector)
    }
}
