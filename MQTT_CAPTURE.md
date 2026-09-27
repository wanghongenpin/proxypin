# MQTT over TLS capture

ProxyPin normally decodes decrypted TLS data as HTTP. This fork selects MQTT
when the first client application bytes contain an MQTT `CONNECT` fixed header
and the `MQTT` or `MQIsdp` protocol name. Other connections continue through
the existing HTTP decoder. Selection does not depend on a hostname or port.

For MQTT, the proxy opens or reuses the upstream TLS connection, relays every
plaintext byte unchanged in both directions, and frames complete MQTT control
packets for display. TCP chunk boundaries can split or combine packets. Packets
larger than 4 MiB are still forwarded but are omitted from capture to limit
memory use. A parser error also disables capture for that connection while
relay continues.

Each MQTT connection appears once in the capture list. Its MQTT tab shows
client and server packets as a directed stream, similar to ProxyPin's
WebSocket view. The packet cards show type, size, and, where available, topic,
packet ID, or CONNACK code. The preview shows the **original binary packet**
as text or hex. These are display records, not HTTP requests sent through
interceptors; MQTT packets do not always have a one-to-one request/response
relationship. The existing history/export system may include the raw packet
bytes, which can contain credentials or private content.
The connection row uses ProxyPin's existing socket-to-process lookup, so an
identified Android app gets its normal icon in MQTT captures too.

This change does not alter certificate validation in client apps. The client
must accept ProxyPin's generated certificate before its decrypted MQTT bytes
can reach the protocol selector. MQTT over WebSocket and unencrypted MQTT are
outside this TLS path.

## Verification

```sh
flutter test test/mqtt_packet_test.dart
flutter build apk --debug
python3 tool/mqtt_proxy_smoke.py --proxy-host PHONE_IP --bind-host MAC_IP
```

The manual smoke test runs temporary local TLS servers, then checks MQTT
CONNECT/CONNACK, PINGREQ/PINGRESP, SUBSCRIBE/SUBACK, incoming PUBLISH, and an
ordinary HTTPS request through the same ProxyPin instance. The proxy must be
running and reachable from the computer on its configured port (default 9099).
