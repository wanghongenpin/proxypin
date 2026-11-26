# Android Root 模式（不占用 VPN）

默认情况下 ProxyPin 在 Android 上通过 `VpnService` 抓包，会占用系统唯一的 VPN 通道，
无法与其它 VPN / 代理类应用同时使用。已 Root 的设备可以开启 **Root 模式**，
改用 iptables 透明代理，完全不建立 VPN。

入口：设置 → Root 模式。

## 工作原理

```
应用 socket ──connect(orig_dst:443)──▶ iptables nat OUTPUT ─▶ PROXYPIN_OUT ─REDIRECT─▶ 127.0.0.1:9099 (ProxyPin)
                                                                                        │
                       /proc/net/tcp：应用 socket 仍记录 src_port → orig_dst、uid ◀───────┘ 按 src_port 反查
```

1. `RootProxyManager` 在 nat 表新建 `PROXYPIN_OUT` 链并挂到 `OUTPUT` 首位：
   - 排除 ProxyPin 自身 uid（避免代理出站连接被重定向成环）、`127.0.0.0/8`、TCP 53；
   - 「代理忽略域名」中的 IP / CIDR / 可解析域名 → `RETURN`；
   - 应用白名单：仅对白名单 uid 执行 `REDIRECT`；黑名单：黑名单 uid `RETURN`，其余 `REDIRECT`；
   - 仅匹配「重定向端口」（默认 `80,443,8080,8443`，留空为全部 TCP）；
   - 远程设备代理（ipProxy）时使用 `DNAT` 到远程代理地址。
2. 代理核心收到的是透明连接（与 VPN 模式一致）：HTTPS 读 SNI，HTTP 读 Host 头。
   需要原始目的地址/端口或来源应用时，Dart 侧照常调用 `getRemoteAddressByPort` / `getProcessByPort`，
   原生侧在 Root 模式下改为读取内核连接表（`/proc/net/tcp{,6}`，必要时经由 su），按应用源端口匹配。
3. 可选增强：
   - **屏蔽 IPv6 TCP**：代理只监听 IPv4，用 `ip6tables` 对被捕获应用的 IPv6 TCP 回 RST，使其回落到 IPv4；
   - **屏蔽 QUIC**：拒绝被捕获应用的 UDP 443，使 HTTP/3 回落到可抓包的 TCP。
4. 按网卡捕获（设置 → Root 模式 →「捕获网卡」）：所选网卡生成 `-o <网卡>` 匹配，只重定向经由这些网卡发出的流量
   （例如只抓 Wi-Fi、不抓移动数据）；不选为全部。IPv6 / QUIC 拒绝规则同样只作用于所选网卡。
5. 捕获热点 / 共享设备：在 nat `PREROUTING` 新建 `PROXYPIN_PRE`，对来自共享网卡（启动时检测到的热点网卡，
   以及 `ap+`、`swlan+`、`softap+`、`wlan1`、`wlan2`、`rndis+`、`ncm+`、`usb+`、`bt-pan+` 等常见命名）的 TCP 执行 `REDIRECT`，
   连接本机热点的电脑 / 手机无需设置代理即可被抓包。这类连接没有本机 uid，应用白/黑名单不适用；
   原始目的地址从 `/proc/net/nf_conntrack` 反查（内核未开启时 HTTPS 按 SNI、HTTP 按 Host 头转发）。
   开启「屏蔽 QUIC / IPv6」时，在 filter `FORWARD` 的 `PROXYPIN_FWD` 中拒绝共享设备的 UDP 443 与 IPv6 TCP。
   需先开启热点再启动抓包（热点网卡在启动时检测）；仅本机代理时生效。
6. `RootProxyService` 作为前台服务保活进程（代理运行在 App 进程内），通知栏提供「停止」。
   规则安装状态记录在 SharedPreferences，App 被强杀后下次启动自动清理残留规则，避免被捕获应用断网。

启动时会重置规则生效前已建立、本该被捕获的直连（filter `OUTPUT` 的 `PROXYPIN_RST`、热点为 `FORWARD` 的 `PROXYPIN_FWD`，
回 TCP RST），否则 Chrome 等复用的 HTTP/2 长连接（同证书子域名还会合并到同一连接）会一直绕过代理。

停止抓包或规则变更（白名单、网卡、热点开关等）时，会主动断开代理上已有的客户端连接：
iptables 的 NAT 只作用于新连接，不断开的话浏览器复用的长连接会继续经过代理（VPN 模式关闭 tun 时这些连接自然断开）。

所有规则都在独立的 `PROXYPIN_OUT` / `PROXYPIN_PRE`（nat）、`PROXYPIN_OUT6`（ip6 filter）、`PROXYPIN_QUIC` / `PROXYPIN_FWD` / `PROXYPIN_RST`（filter）链中，
停止时整体删除，不影响系统和其它应用的规则。

## 手动排查

```bash
adb shell su -c 'iptables -t nat -S PROXYPIN_OUT'
adb shell su -c 'ip6tables -S PROXYPIN_OUT6; iptables -S PROXYPIN_QUIC'
# 手动清理
adb shell su -c 'iptables -t nat -D OUTPUT -j PROXYPIN_OUT; iptables -t nat -F PROXYPIN_OUT; iptables -t nat -X PROXYPIN_OUT'
```

## 已知限制

- 仅 TCP；UDP（除 QUIC 拒绝外）不经过代理。
- VPN 模式无法按网卡选择：VpnService 只能接管路由进入 tun 的流量，无法区分其后实际走哪张物理网卡。
- 证书：HTTPS 解密仍需应用信任 ProxyPin CA。Root 设备可把 CA 安装为系统证书（如 Magisk 模块）。
- 重定向端口留空时非 HTTP 协议也会进入代理，可能导致部分应用异常，建议按需指定端口。

## 代码位置

| 文件 | 说明 |
| --- | --- |
| `android/.../root/RootShell.kt` | 常驻 su shell，命令输出用随机标记分隔 |
| `android/.../root/RootProxyManager.kt` | iptables 规则生成/安装/清理，连接反查 |
| `android/.../root/TcpConnectionTable.kt` | `/proc/net/tcp{,6}` 解析 |
| `android/.../root/NetInterfaces.kt` | 网卡枚举与类型识别（原始抓包、按网卡捕获共用） |
| `android/.../root/RootProxyService.kt` | 前台保活服务 |
| `android/.../plugin/RootProxyPlugin.kt` | `com.proxy/rootProxy` 方法通道 |
| `lib/native/root_proxy.dart` | Dart 封装 |
| `lib/native/vpn.dart` | 按配置在 VPN / Root 间分发，上层调用无需区分 |
| `lib/ui/mobile/setting/root_mode.dart` | 设置页 |

---

# 原始抓包（Root + 内置 tcpdump）

入口：工具箱 →「原始抓包」，或 设置 → Root 模式 →「原始抓包」。

- 内置 tcpdump 4.99.5 / libpcap 1.10.5（静态链接，arm64-v8a 与 armeabi-v7a 各约 520KB 压缩体积），
  由 `tool/tcpdump/build_tcpdump.sh` 用 NDK 交叉编译生成，产物位于 `android/app/src/main/assets/tcpdump/`。
- 以 root 执行 `tcpdump -i <网卡> -U -n -s <snaplen> -w - [BPF]`，pcap 流经 stdout 读出：
  - 完整写入 `cache/pcap/capture-*.pcap`（保留最近 10 个），可分享 / 保存，用 Wireshark 打开；
  - 同时分批推送给 Dart 侧实时解析展示（内存最多缓存 20 万包 / 96MB，超出后仅写文件）。
- 抓包参数（网卡 / BPF / 截取长度）会记住上次选择；网卡列表显示类型（Wi-Fi / 移动数据 / VPN / 热点）、是否连接与 IP，
  未连接的网卡置灰排在后面。VPN 模式下选择 `any` 会同时抓到 tun 与真实网卡上的同一份流量，可改选真实网卡去重。
- 若 SELinux 不允许执行应用私有目录中的二进制，会自动复制到 `/data/local/tmp` 重试。
- 解析支持 LINUX_SLL2（`-i any`）、LINUX_SLL、Ethernet（含 VLAN）、RAW；IPv4/IPv6、TCP/UDP/ICMP；
  应用层识别 DNS（查询/应答，并用应答把 IP 反查为域名）、TLS ClientHello SNI、HTTP 请求/响应行、QUIC。
- 按「流」（协议 + 双端地址端口）聚合，异步通过 `/proc/net/{tcp,udp}{,6}` 反查所属应用。
- 导出：完整 pcap，或只导出当前筛选结果 / 单条流。
- HTTPS / QUIC 内容为密文，只能看到域名（SNI）、IP、端口、大小等元数据；要看明文请用代理抓包（MITM），或见下文的 TLS 密钥嵌入。

## 导出 pcapng 自动解密 HTTPS

抓包期间 ProxyPin 会记录**自身上游 TLS 连接**（ProxyPin → 真实服务器）的会话密钥（NSS Key Log 格式），
导出时写入 pcapng 的 Decryption Secrets Block（`TLSK`）。用 Wireshark 打开即自动解密，无需配置 keylog 文件。

- 适用：开启 Root 模式（或 VPN）+ HTTPS 抓包，被 ProxyPin 解密转发的连接，其上游段走真实网卡，可被 tcpdump 抓到并解密；
  支持 TLS 1.2 / 1.3。
- 不适用：App → ProxyPin（127.0.0.1:代理端口）这一段。Dart `SecureSocket.secureServer` 没有开放 keyLog，
  Wireshark 中可用 `not tcp.port == 9099` 过滤；证书锁定 / 未开启 HTTPS 抓包 / 过滤名单内的直通连接也无法解密。
- 只记录抓包开始之后新建的连接；抓包前已建立的长连接没有密钥（可强制停止目标 App 让其重连）。
- 配置了重写规则时，解密看到的是改写后真正发给服务器的内容。
- 仍可选择导出不含密钥的原始 pcap。

验证：`test/pcapng_test.dart`（块结构 + tshark 解密样本）与 `test/e2e/keylog_proxy_e2e_test.dart`
（真实 ProxyServer MITM → HTTPS 服务器，tcpdump 抓包，tshark 不带 keylog 参数解密出上游请求）。

# 高级筛选语法

HTTP 请求列表的搜索框与原始抓包列表共用一套语法（点击搜索框右侧的筛选图标查看全部字段，点示例即可插入）：

| 写法 | 含义 |
| --- | --- |
| `a b` | 并且 |
| `a \| b` 或 `a OR b` | 或者 |
| `-a` / `!a` | 取反 |
| `field:value` | 字段包含（忽略大小写） |
| `host:*.example.com` | `*` 通配（整体匹配） |
| `url:/v\d+/` | 正则 |
| `body:"hello world"` | 带空格的值 |
| `method:GET,POST` | 多选 |
| `status:4xx`、`status:400-499`、`status>=500`、`status!=200` | 状态码类别 / 范围 / 比较 |
| `size>100k`、`time>1s` | 数值比较，支持 k/m、ms/s 单位 |

HTTP 字段：method、host、path、url、query、status、type、reqtype、size、reqsize、time、header、reqheader、resheader、
body、reqbody、resbody、cookie、app、port、ip（客户端 / 远程 IP）、proto、is（pending/error/ok/redirect/ws/sse/https/h2/graphql/cookie/large/slow/remote/local）。

`is:remote`：来自其它设备（热点 / USB 共享 / 局域网设置代理）的请求——客户端地址不是回环或本机网卡地址，且未反查到本机应用；`is:local` 相反。

原始抓包字段：proto（tcp/udp/icmp/dns/tls/http/quic/ipv4/ipv6）、host、ip、src、dst、port、sport、dport、app、bytes、
packets、time、info、is（open/closed/reset/syn/oneway/large/named）。

不含字段语法时保持原有的整串文本搜索行为；勾选「正则」时不启用该语法。
