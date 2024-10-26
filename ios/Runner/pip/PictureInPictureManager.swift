//
//  PictureInPicturePlugin.swift
//  Runner
//
//  Created by wanghongen on 2024/1/8.
//

import AVKit
import UIKit
import Flutter
import SnapKit
import SwiftUI

@available(iOS 13.0.0, *)
class PictureInPictureManager: NSObject,AVPictureInPictureControllerDelegate {

    static var shared: PictureInPictureManager!
    private var channel: FlutterMethodChannel;
    //播放器
    private var playerLayer: AVPlayerLayer?

    // 画中画
    var pipController: AVPictureInPictureController!
    var pipView: PictureInPictureView?
    
    var proxyPort :Int = -1;
    
    static func regirst(flutter: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel.init(name: "com.proxy/pictureInPicture", binaryMessenger: flutter);
        shared  = PictureInPictureManager(channel: channel)
    }
    
    private init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()

        channel.setMethodCallHandler({(call: FlutterMethodCall, result: FlutterResult) -> Void in
//            print("画中画 {call.method} methodCallHandler：\(UIApplication.shared.windows)")
            if ("enterPictureInPictureMode" == call.method) {
                let arguments = call.arguments as? Dictionary<String, AnyObject>
                self.proxyPort = arguments?["proxyPort"] as! Int
                self.starPiP()
                result(Bool(true))
            } else if ("addData" == call.method) {
                self.pipView?.addData(text: call.arguments as! String)
                
            }
        })
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print(error)
            }
        }
    }
    
    private func initPIP() {
        if (playerLayer == nil) {
            setupPlayer()
        }
            
        if (pipController == nil) {
            print("画中画初始化：\(UIApplication.shared.windows)")
            setupPip()
        }
    }
    
    // 配置播放器
    private func setupPlayer() {
        let video = Bundle.main.url(forResource: "silience", withExtension: "mov")
        let asset = AVAsset.init(url: video!)
        let playerItem = AVPlayerItem.init(asset: asset)
  
        let player = AVPlayer.init(playerItem: playerItem)
        
        playerLayer = AVPlayerLayer(player: player)

        playerLayer?.frame = .init(x: 90, y: 390, width: 180, height: 280)
        playerLayer?.isHidden = true
        player.isMuted = true
        player.allowsExternalPlayback = true
//        player.play()
        let view =  UIView()
        view.layer.addSublayer(playerLayer!)

        UIApplication.shared.keyWindow?.rootViewController?.view.addSubview(view)
    }
    
    // 配置画中画
    private func setupPip() {
        pipController = AVPictureInPictureController.init(playerLayer: playerLayer!)!
        pipController.delegate = self
//        if #available(iOS 14.2, *) {
//            pipController.canStartPictureInPictureAutomaticallyFromInline = true
//        }
    
        // 隐藏播放按钮、快进快退按钮
        pipController.setValue(1, forKey: "controlsStyle")
        //点击回到app
        //pipController.setValue(2, forKey: "controlsStyle")
    }
    
    
    // 开启/关闭 画中画
    func starPiP() {
        self.initPIP();
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            print("starPiP \(pipController.isPictureInPicturePossible)")

            if (pipController.isPictureInPicturePossible) {
                pipController.startPictureInPicture()
                return;
            }
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) { [self] in
                if (self.pipController.isPictureInPicturePossible) {
                    self.pipController.startPictureInPicture()
                    return;
                }
                
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2) {
                    self.pipController.startPictureInPicture()
                }
            }
        }
    }
    
    var playButton  = UIButton(type: .custom)
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
//        print("画中画初始化后：\(UIApplication.shared.windows)")
        
       // 把自定义view加到画中画上
        if let window = UIApplication.shared.windows.first {
            pipView = PictureInPictureView()
            let vc = UIHostingController(rootView: pipView)
             
            let icon = VpnManager.shared.isRunning() ? "pause.fill" : "play.fill"
            playButton.setImage(UIImage(systemName: icon), for: .normal)
            playButton.addTarget(self, action: #selector(vpnAction), for: .touchUpInside)

            vc.view.addSubview(playButton)
            playButton.snp.makeConstraints{ (make) in
                make.left.equalTo(15)
                make.bottom.equalTo(-13)
            }
            
            let clearButton  = UIButton(type: .custom)
            clearButton.setImage(UIImage(systemName: "trash.circle"), for: .normal)
            clearButton.addTarget(self, action: #selector(cleanAction), for: .touchUpInside)

            vc.view.addSubview(clearButton)
            clearButton.snp.makeConstraints{ (make) in
                make.right.equalTo(-13)
                make.bottom.equalTo(-13)
            }
            
            window.addSubview(vc.view!)
            // 使用自动布局
            vc.view?.snp.makeConstraints { (make) -> Void in
                make.edges.equalToSuperview()
            }
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
    
    @objc func cleanAction() {
        channel.invokeMethod("cleanSession", arguments: nil)
        pipView?.dataSource.clear()
    }
    
    @objc func vpnAction() {
        if (VpnManager.shared.isRunning()) {
            VpnManager.shared.disconnect()
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            VpnManager.shared.connect(host: nil, port: proxyPort, ipProxy: nil)
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
//        pipView?.addData(text: "hello")
    }
    
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
//        print("pictureInPictureControllerWillStopPictureInPicture：")
        channel.invokeMethod("exitPictureInPictureMode", arguments: nil)
    }

}
