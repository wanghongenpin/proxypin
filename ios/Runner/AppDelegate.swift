import UIKit
import Flutter
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    var backgroundAudioEnable: Bool = true
    
    override func application(_ application: UIApplication,
                              didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller: FlutterViewController = window.rootViewController as! FlutterViewController ;
        let vpnChannel = FlutterMethodChannel.init(name: "com.proxy/proxyVpn", binaryMessenger: controller as! FlutterBinaryMessenger);
            vpnChannel.setMethodCallHandler({(call: FlutterMethodCall, result: FlutterResult) -> Void in
                if ("stopVpn" == call.method) {
                    VpnManager.shared.disconnect()
                } else if ("isRunning" == call.method){
                    result(Bool(VpnManager.shared.isRunning()))
                } else if ("restartVpn" == call.method){
                    let arguments = call.arguments as? Dictionary<String, AnyObject>
//                     VpnManager.shared.disconnect()
                    VpnManager.shared.restartConnect(host: arguments?["proxyHost"] as? String ,port: arguments?["proxyPort"] as? Int, ipProxy: arguments?["ipProxy"] as? Bool)
                } else {
                    let arguments = call.arguments as? Dictionary<String, AnyObject>
                    VpnManager.shared.connect(host: arguments?["proxyHost"] as? String ,port: arguments?["proxyPort"] as? Int, ipProxy: arguments?["ipProxy"] as? Bool)
              }
          })
      
        if #available(iOS 13.0.0, *) {
            PictureInPictureManager.regirst(flutter: controller as! FlutterBinaryMessenger)
            MethodHandler.register(with: self.registrar(forPlugin: MethodHandler.name)!)
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
   }

    override func applicationWillTerminate(_ application: UIApplication) {
        VpnManager.shared.disconnect()
    }

    var timer: Timer?
    var bgTask: UIBackgroundTaskIdentifier?

    override func applicationDidEnterBackground(_ application: UIApplication) {
        if (!VpnManager.shared.isRunning()) {
            return
        }
    
        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(timerAction), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: RunLoop.Mode.common)
               bgTask = application.beginBackgroundTask(expirationHandler: nil)
    }

    @objc func timerAction() {
        print(UIApplication.shared.backgroundTimeRemaining)
        let application = UIApplication.shared
        
        if (bgTask != nil) {
            application.endBackgroundTask(bgTask!);
            bgTask = nil;
        }
        
        if (UIApplication.shared.backgroundTimeRemaining < 60 && VpnManager.shared.isRunning()) {
            bgTask = application.beginBackgroundTask(expirationHandler: nil)
        }
            
        if (application.backgroundTimeRemaining <= 0 || application.applicationState == .active || AudioManager.shared.openBackgroundAudioAutoplay) {
            timer?.invalidate();
            timer = nil;
        }
        
        if (application.backgroundTimeRemaining <= 10) {
            self.backgroundAudio()
        }

    }

    override func applicationWillResignActive(_ application: UIApplication) {
        self.backgroundAudio();
    }
    override  func applicationDidBecomeActive(_ application: UIApplication) {
        self.endBackgroundUpdateTask()
    }
    
    private func backgroundAudio() {
        if (!VpnManager.shared.isRunning() || !self.backgroundAudioEnable) {
            return
        }
        if (AudioManager.shared.openBackgroundAudioAutoplay) {
            return;
        }
        
        AudioManager.shared.openBackgroundAudioAutoplay = true
        self.backgroundUpdateTask = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.endBackgroundUpdateTask()
        })
    }
    
    var backgroundUpdateTask: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier(rawValue: 0)
    
    func endBackgroundUpdateTask() {
        if (!VpnManager.shared.isRunning() || !AudioManager.shared.openBackgroundAudioAutoplay) {
            return
        }

        AudioManager.shared.openBackgroundAudioAutoplay = false
        UIApplication.shared.endBackgroundTask(self.backgroundUpdateTask)
        self.backgroundUpdateTask = UIBackgroundTaskIdentifier.invalid
    }

}
