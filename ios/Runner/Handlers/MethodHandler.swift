//
//  MethodHandler.swift
//  Runner
//
//  Created by wanghongen on 2025/5/30.
//

import Flutter
import Network
import SystemConfiguration.CaptiveNetwork
import Security

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
                print("[MethodHandler] requestLocalNetwork result: \(isAvailable)")
                result(isAvailable)
            }
        case "isCaInstalled":
            guard let args = call.arguments as? [String: Any], let pem = args["pem"] as? String else {
                print("[MethodHandler] isCaInstalled ARG_ERROR: missing pem")
                result(FlutterError(code: "ARG_ERROR", message: "Missing pem", details: nil))
                return
            }
            let ret = self.isCertificateInstalled(pem: pem)
            result(ret)
        case "evaluateChainTrusted":
            guard let args = call.arguments as? [String: Any], let leafPem = args["leafPem"] as? String, let caPem = args["caPem"] as? String else {
                print("[MethodHandler] evaluateChainTrusted ARG_ERROR: missing leafPem/caPem")
                result(FlutterError(code: "ARG_ERROR", message: "Missing leafPem/caPem", details: nil))
                return
            }
            let host = args["host"] as? String
            let ret = self.isChainTrusted(leafPem: leafPem, caPem: caPem, host: host)
//             print("[MethodHandler] evaluateChainTrusted => \(ret)")
            result(ret)
        default:
            print("[MethodHandler] method not implemented: \(call.method)")
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - iOS: Check certificate trust
    private func isCertificateInstalled(pem: String) -> Bool {
        guard let der = self.decodePemToDer(pem) as CFData?, let certificate = SecCertificateCreateWithData(nil, der) else {
            print("[MethodHandler] isCertificateTrusted decode/create cert failed")
            return false
        }
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        if status != errSecSuccess || trust == nil {
            print("[MethodHandler] SecTrustCreateWithCertificates failed status=\(status)")
            return false
        }
        if #available(iOS 12.0, *) {
            var error: CFError?
            let ok = SecTrustEvaluateWithError(trust!, &error)
            if let e = error {
                print("[MethodHandler] SecTrustEvaluateWithError ok=\(ok) error=\(e)")
            }
            return ok
        } else {
            var trustResult = SecTrustResultType.invalid
            let evalStatus = SecTrustEvaluate(trust!, &trustResult)
            let ok = (evalStatus == errSecSuccess) && (trustResult == .unspecified || trustResult == .proceed)
            print("[MethodHandler] SecTrustEvaluate status=\(evalStatus) result=\(trustResult.rawValue) trusted=\(ok)")
            return ok
        }
    }

    // MARK: - iOS: Evaluate leaf+CA chain with SSL policy
    private func isChainTrusted(leafPem: String, caPem: String, host: String?) -> Bool {
        guard let leafDer = self.decodePemToDer(leafPem) as CFData?, let leaf = SecCertificateCreateWithData(nil, leafDer) else {
            print("[MethodHandler] isChainTrusted leaf decode/create failed")
            return false
        }
        guard let caDer = self.decodePemToDer(caPem) as CFData?, let ca = SecCertificateCreateWithData(nil, caDer) else {
            print("[MethodHandler] isChainTrusted ca decode/create failed")
            return false
        }
        let certs: [SecCertificate] = [leaf, ca]
        let policy = SecPolicyCreateSSL(true, host as CFString?)
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certs as CFTypeRef, policy, &trust)
        if status != errSecSuccess || trust == nil {
            print("[MethodHandler] isChainTrusted SecTrustCreateWithCertificates failed status=\(status)")
            return false
        }
        if #available(iOS 12.0, *) {
            var error: CFError?
            let ok = SecTrustEvaluateWithError(trust!, &error)
            if let e = error { print("[MethodHandler] isChainTrusted evaluate ok=\(ok) error=\(e)") } else { print("[MethodHandler] isChainTrusted evaluate ok=\(ok)") }
            return ok
        } else {
            var trustResult = SecTrustResultType.invalid
            let evalStatus = SecTrustEvaluate(trust!, &trustResult)
            let ok = (evalStatus == errSecSuccess) && (trustResult == .unspecified || trustResult == .proceed)
//             print("[MethodHandler] isChainTrusted evaluate status=\(evalStatus) result=\(trustResult.rawValue) trusted=\(ok)")
            return ok
        }
    }

    private func decodePemToDer(_ pem: String) -> Data? {
        // Strip header/footer and whitespace
        let lines = pem.components(separatedBy: "\n").filter { line in
            return !line.contains("-----BEGIN") && !line.contains("-----END") && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let base64Str = lines.joined()
        let der = Data(base64Encoded: base64Str, options: .ignoreUnknownCharacters)
        return der
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
