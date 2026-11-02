"""Manual end-to-end check for a running ProxyPin instance.

Runs local MQTT-over-TLS and HTTPS upstream servers, then sends both through
ProxyPin's HTTP CONNECT port. Example:

    python3 tool/mqtt_proxy_smoke.py --proxy-host 192.168.1.20 \
        --bind-host 192.168.1.10

Requires openssl in PATH. The test certificate is temporary and the TLS
client deliberately does not verify the local proxy's generated certificate.
"""

import argparse
import socket
import ssl
import subprocess
import tempfile
import threading
from pathlib import Path


def read_exact(sock, count):
    data = bytearray()
    while len(data) < count:
        part = sock.recv(count - len(data))
        if not part:
            raise EOFError(f"socket closed after {len(data)} of {count} bytes")
        data.extend(part)
    return bytes(data)


def read_headers(sock):
    data = bytearray()
    while not data.endswith(b"\r\n\r\n"):
        data.extend(read_exact(sock, 1))
        if len(data) > 65536:
            raise ValueError("header limit exceeded")
    return bytes(data)


def connect_via_proxy(proxy_host, proxy_port, target_host, target_port):
    sock = socket.create_connection((proxy_host, proxy_port), timeout=15)
    sock.settimeout(15)
    sock.sendall(
        f"CONNECT {target_host}:{target_port} HTTP/1.1\r\n"
        f"Host: {target_host}:{target_port}\r\n\r\n".encode()
    )
    response = read_headers(sock)
    if not response.startswith(b"HTTP/1.1 200"):
        raise AssertionError(f"CONNECT failed: {response!r}")
    context = ssl._create_unverified_context()
    return context.wrap_socket(sock, server_hostname="mqtt-smoke.test")


def run_server(listener, server_context, kind, errors):
    try:
        raw, _ = listener.accept()
        raw.settimeout(15)
        with raw, server_context.wrap_socket(raw, server_side=True) as conn:
            if kind == "mqtt":
                connect = read_exact(conn, 18)
                assert connect == bytes.fromhex("101000044d5154540402003c000474657374"), connect.hex()
                conn.sendall(bytes.fromhex("20020000"))
                assert read_exact(conn, 2) == bytes.fromhex("c000")
                conn.sendall(bytes.fromhex("d000"))
                assert read_exact(conn, 10) == bytes.fromhex("820800010003612f6200")
                conn.sendall(bytes.fromhex("9003000100"))
                conn.sendall(bytes.fromhex("30060003612f6278"))
            else:
                request = read_headers(conn)
                assert request.startswith(b"GET /probe HTTP/1.1"), request
                conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK")
    except Exception as error:
        errors.append(error)
    finally:
        listener.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proxy-host", required=True)
    parser.add_argument("--proxy-port", type=int, default=9099)
    parser.add_argument("--bind-host", required=True, help="Local IP reachable by ProxyPin")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory() as directory:
        cert = Path(directory) / "cert.pem"
        key = Path(directory) / "key.pem"
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-days", "1", "-subj", "/CN=mqtt-smoke.test", "-keyout", str(key),
             "-out", str(cert)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        server_context.load_cert_chain(cert, key)
        errors = []

        for kind in ("mqtt", "https"):
            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind((args.bind_host, 0))
            listener.listen(1)
            listener.settimeout(15)
            port = listener.getsockname()[1]
            thread = threading.Thread(
                target=run_server, args=(listener, server_context, kind, errors), daemon=True
            )
            thread.start()
            with connect_via_proxy(args.proxy_host, args.proxy_port, args.bind_host, port) as conn:
                if kind == "mqtt":
                    conn.sendall(bytes.fromhex("101000044d5154540402003c000474657374"))
                    assert read_exact(conn, 4) == bytes.fromhex("20020000")
                    conn.sendall(bytes.fromhex("c000"))
                    assert read_exact(conn, 2) == bytes.fromhex("d000")
                    conn.sendall(bytes.fromhex("820800010003612f6200"))
                    assert read_exact(conn, 5) == bytes.fromhex("9003000100")
                    assert read_exact(conn, 8) == bytes.fromhex("30060003612f6278")
                else:
                    conn.sendall(b"GET /probe HTTP/1.1\r\nHost: mqtt-smoke.test\r\n\r\n")
                    assert read_headers(conn).startswith(b"HTTP/1.1 200 OK")
                    assert read_exact(conn, 2) == b"OK"
            thread.join(timeout=16)
            if errors:
                raise errors[0]
            print(f"{kind}: passed")


if __name__ == "__main__":
    main()
