//
//  MethodHandler.swift
//  Runner
//
//  Created by wanghongen on 2025/5/30.
//

import Flutter
import Network
import SystemConfiguration.CaptiveNetwork

public class MethodHandler: NSObject, FlutterPlugin {
    public static let name = "com.proxypin/method"

    private var channel: FlutterMethodChannel?
    private var currentPathMonitor: NWPathMonitor?
    private var currentCompletionHandler: ((Bool) -> Void)?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: Self.name, binaryMessenger: registrar.messenger())
        let instance = MethodHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.channel = channel
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestLocalNetwork":
            // 调用异步函数，并在其完成时传递结果
            self.requestLocalNetworkAccess { isAvailable in
                result(isAvailable)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 异步检查本地网络（Wi-Fi 或以太网）是否可用。
    /// - Parameter completion: 一个回调函数，当检查完成时调用，参数为 Bool 类型，true 表示本地网络可用，false 表示不可用。
    func requestLocalNetworkAccess(completion: @escaping (Bool) -> Void) {

        // 如果已有正在进行的监视，先取消它
        self.currentPathMonitor?.cancel()

        self.currentPathMonitor = NWPathMonitor()
        // 将 completion 存储起来，以便在 pathUpdateHandler 中调用
        // 这是为了确保 completion 只被调用一次
        self.currentCompletionHandler = completion

        self.currentPathMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            // 确保 completionHandler 仍然存在（即尚未被调用和清除）
            guard let completionHandler = self.currentCompletionHandler else {
                // 可能已经被调用过了，或者监视器被意外触发
                // 为安全起见，取消监视器
                self.currentPathMonitor?.cancel()
                return
            }

            var isLocalNetworkAvailable = false
            print("Network path status: \(path.status)")
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                    isLocalNetworkAvailable = true
                }
            }
            // 对于其他状态 (例如 .unsatisfied, .requiresConnection) 或其他接口类型 (例如 cellular),
            // isLocalNetworkAvailable 将保持 false。

            // 调用存储的 completion handler
            completionHandler(isLocalNetworkAvailable)

            // 清理：取消监视器并清除存储的引用，以防止重复调用和内存泄漏
            self.currentPathMonitor?.cancel()
            self.currentPathMonitor = nil
            self.currentCompletionHandler = nil
        }

        // 在主队列上启动监视器
        self.currentPathMonitor?.start(queue: DispatchQueue.global())
    }
}
