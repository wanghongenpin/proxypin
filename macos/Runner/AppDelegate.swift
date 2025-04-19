import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                if !window.isVisible {
                    window.setIsVisible(true)
                }
                window.makeKeyAndOrderFront(self)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
    
    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }

    override func applicationWillTerminate(_ notification: Notification) {
        AppLifecycleChannel.appDetached()
        NSLog("applicationWillTerminate")
    }
    
}
