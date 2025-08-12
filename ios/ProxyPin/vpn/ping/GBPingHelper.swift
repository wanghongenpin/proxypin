//
//  GBPingHelper.swift
//

import Foundation

public typealias Handler = ((_ response: [String: Any]) -> Void)

public class GBPingHelper: NSObject {
  private var ping: GBPing?
  private let delegate = PingDelegate()

  func start(withHost host: String, ipv4: Bool, ipv6: Bool, count: UInt, interval: TimeInterval, timeout: TimeInterval, ttl: UInt, handler: @escaping Handler) {
    ping?.stop()
    ping = GBPing()
    guard let ping = ping else {
      return
    }
    ping.host = host
    ping.useIpv4 = ipv4
    ping.useIpv6 = ipv6
    ping.count = count
    ping.pingPeriod = interval
    ping.timeout = timeout
    if ttl > 0 {
      ping.ttl = ttl
    }

    delegate.handler = handler
    ping.delegate = delegate
    ping.setup { success, err in
      if let err = err as NSError? {
        if err.domain == kCFErrorDomainCFNetwork as String {
          handler(["error": "UnknownHost"])
        } else {
          handler(["error": "UnknownError"])
        }
        return
      }
      if success {
        self.delegate.transmitted = 0
        self.delegate.received = 0
        ping.startPinging()
      }
    }
  }

  func stop() {
    ping?.stop()
  }
}

private class PingDelegate: NSObject, GBPingDelegate {
  public var handler: Handler?
  public var transmitted = 0
  public var received = 0

  func handle(_ summary: GBPingSummary, error: String? = nil) {
    guard let handler = handler else {
      return
    }
    var ret: [String: Any] = [:]
    ret["seq"] = summary.sequenceNumber
    ret["host"] = summary.host
    ret["ip"] = summary.ip
    ret["ttl"] = summary.ttl
    ret["time"] = summary.rtt
    ret["error"] = error
    handler(ret)
  }

  func ping(_ pinger: GBPing, didSendPingWith summary: GBPingSummary) {
    transmitted += 1
  }

  func ping(_ pinger: GBPing, didTimeoutWith summary: GBPingSummary) {
    handle(summary, error: "RequestTimedOut")
  }

  func ping(_ pinger: GBPing, didReceiveReplyWith summary: GBPingSummary) {
    received += 1
    handle(summary)
  }

  func ping(_ pinger: GBPing, didFinishWithTime time: TimeInterval) {
    guard let handler = handler else {
      return
    }
    var ret: [String: Any] = [:]
    ret["time"] = time
    ret["received"] = received
    ret["transmitted"] = transmitted
    handler(ret)
  }
}
