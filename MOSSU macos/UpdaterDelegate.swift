
import AppKit
import Sparkle

class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func updaterWillShowUpdateAlert(_ updater: SPUUpdater, for item: SUAppcastItem) {
        NSApp.setActivationPolicy(.regular)
    }
    
    func updaterDidDismissUpdateAlert(_ updater: SPUUpdater) {
        NSApp.setActivationPolicy(.accessory)
    }
}
