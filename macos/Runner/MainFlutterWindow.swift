import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    // Offsets from the top-left corner of the title bar container (in points)
    // Tweak these to your preferred locations.
    private let closeButtonTopLeftOffset = NSPoint(x: 10, y: 13)
    private let miniaturizeButtonTopLeftOffset = NSPoint(x: 32, y: 13)
    private let zoomButtonTopLeftOffset = NSPoint(x: 52, y: 13)

    // Whether to auto-apply on window events
    private let shouldAutoApplyTrafficLightPositions = true
    private var trafficLightObserversRegistered = false

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        AppLifecycleChannel.registerChannel(flutterViewController: flutterViewController)

        RegisterGeneratedPlugins(registry: flutterViewController)

        super.awakeFromNib()

        // Apply custom positions for traffic-light buttons and observe changes
        if shouldAutoApplyTrafficLightPositions {
            applyTrafficLightButtonPositions()
            registerWindowObservers()
        }
    }

    deinit {
        unregisterWindowObservers()
    }

    // MARK: - Traffic-light buttons positioning

    private func applyTrafficLightButtonPositions() {
        // Skip in full screen; macOS manages buttons differently there
        if self.styleMask.contains(.fullScreen) { return }

        setStandardWindowButton(.closeButton, topLeftOffset: closeButtonTopLeftOffset)
        setStandardWindowButton(.miniaturizeButton, topLeftOffset: miniaturizeButtonTopLeftOffset)
        setStandardWindowButton(.zoomButton, topLeftOffset: zoomButtonTopLeftOffset)
    }

    private func setStandardWindowButton(_ type: NSWindow.ButtonType, topLeftOffset: NSPoint) {
        guard let button = self.standardWindowButton(type), let container = button.superview else { return }

        // Ensure autoresizing mask changes are respected when moving via frames
        button.translatesAutoresizingMaskIntoConstraints = true

        // Convert a top-left based offset to the container's default bottom-left coordinate system
        let containerHeight = container.bounds.height
        let targetY = containerHeight - topLeftOffset.y - button.frame.height
        let targetX = topLeftOffset.x
        let newOrigin = NSPoint(x: max(0, targetX), y: max(0, targetY))

        // Avoid redundant layout churn
        if button.frame.origin.equalTo(newOrigin) { return }
        button.setFrameOrigin(newOrigin)
    }

    private func registerWindowObservers() {
        guard !trafficLightObserversRegistered else { return }
        trafficLightObserversRegistered = true
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowDidResize(_:)), name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowDidEndLiveResize(_:)), name: NSWindow.didEndLiveResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowDidExitFullScreen(_:)), name: NSWindow.didExitFullScreenNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(onWindowDidEnterFullScreen(_:)), name: NSWindow.didEnterFullScreenNotification, object: self)
    }

    private func unregisterWindowObservers() {
        if trafficLightObserversRegistered {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: self)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEndLiveResizeNotification, object: self)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: self)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: self)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: self)
            trafficLightObserversRegistered = false
        }
    }

    @objc private func onWindowDidResize(_ notification: Notification) {
        applyTrafficLightButtonPositions()
    }

    @objc private func onWindowDidEndLiveResize(_ notification: Notification) {
        applyTrafficLightButtonPositions()
    }

    @objc private func onWindowDidBecomeKey(_ notification: Notification) {
        applyTrafficLightButtonPositions()
    }

    @objc private func onWindowDidExitFullScreen(_ notification: Notification) {
        // Re-apply after leaving full screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.applyTrafficLightButtonPositions()
        }
    }

    @objc private func onWindowDidEnterFullScreen(_ notification: Notification) {
        // No-op; let system manage buttons
    }
}
