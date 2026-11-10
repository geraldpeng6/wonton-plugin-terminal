#!/usr/bin/env python3
# 入口页的后端：宿主地址、公钥、连接预检、密钥撤销/重新生成。只监听回环，nginx 把 /wonton/api/ 转到这里，
# 外网只经核心网关（网关已验主人会话、只放行同源请求）。只用标准库。
import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STATE = "/data/state"
CONFIG = os.path.join(STATE, "host")
KEY = os.path.join(os.environ.get("HOME", "/data/home"), ".ssh", "id_ed25519")
PORT = 8081


def default_host() -> str:
    # 容器默认路由的网关就是宿主在插件网络里的地址（核心压低自己的网关优先级，默认路由在这里是宿主）。
    with open("/proc/net/route", encoding="ascii") as routes:
        next(routes)
        for line in routes:
            fields = line.split()
            if len(fields) > 3 and fields[1] == "00000000" and int(fields[3], 16) & 0x2:
                return ".".join(str(int(fields[2][i : i + 2], 16)) for i in (6, 4, 2, 0))
    return ""


def config() -> dict:
    host, port = default_host(), 22
    try:
        with open(CONFIG, encoding="utf-8") as handle:
            saved = handle.read().splitlines()
        host = (saved[0] if saved and saved[0].strip() else host)
        port = int(saved[1]) if len(saved) > 1 and saved[1].strip() else port
    except (FileNotFoundError, ValueError):
        pass
    return {"host": host, "port": port, "default_host": default_host()}


def save_config(host: str, port: int) -> dict:
    os.makedirs(STATE, exist_ok=True)
    with open(CONFIG, "w", encoding="utf-8") as handle:
        handle.write(f"{host}\n{port}\n")
    return config()


def public_key() -> str:
    try:
        with open(KEY + ".pub", encoding="ascii") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return ""


def regenerate() -> str:
    for path in (KEY, KEY + ".pub"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
    subprocess.run(
        ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "wonton-terminal", "-f", KEY],
        check=True,
    )
    return public_key()


def revoke() -> None:
    for path in (KEY, KEY + ".pub"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def known_fingerprint(host: str, port: int) -> str:
    result = subprocess.run(
        ["ssh-keygen", "-F", f"[{host}]:{port}" if port != 22 else host],
        capture_output=True, text=True,
    )
    for line in result.stdout.splitlines():
        if line and not line.startswith("#"):
            fields = line.split()
            if len(fields) > 2:
                return f"{fields[1]} {fields[2]}"
    return ""


def classify(stderr: str, debug: str) -> tuple[str, str, str]:
    """把 ssh 的失败分成三类：连不上、公钥没加、认证过了但被拒（root 不许登录这类）。"""
    text = (stderr or "") + (debug or "")
    if re.search(r"Connection refused|No route to host|Network is unreachable|timed out|Connection timed out", text):
        return (
            "unreachable",
            "连不上宿主，sshd 可能没开或端口不对。",
            "确认宿主开了 sshd、地址和端口填对了，再点“试一次”。",
        )
    if "Server accepts key:" in (debug or "") or "Authenticated to" in (debug or ""):
        return (
            "refused",
            "密钥认过了，但宿主不让 root 登录。",
            "看宿主 /etc/ssh/sshd_config 的 PermitRootLogin（改成 prohibit-password 或 yes 后重启 sshd），或换一个有 sudo 的账号。",
        )
    if "Permission denied" in text:
        return (
            "key",
            "宿主没认这把公钥。",
            "先把上面的公钥加到宿主 root 的 ~/.ssh/authorized_keys，再点“试一次”。",
        )
    if "Host key verification failed" in text:
        return (
            "hostkey",
            "宿主的主机指纹变了或对不上。",
            "核对一下指纹；确认没错就从 known_hosts 里删掉旧的那一行再试。",
        )
    if "Could not resolve hostname" in text:
        return ("unreachable", "解析不了填的地址。", "换成 IP 或宿主能解析的名字。")
    return ("other", "连接没成，原因看下面的详情。", "看完详情再试一次。")


def test_connection() -> dict:
    cfg = config()
    host, port = cfg["host"], cfg["port"]
    if not host:
        return {"ok": False, "class": "unreachable", "message": "没拿到宿主地址。", "next": "填上地址再试。", "detail": "", "fingerprint": ""}
    if not public_key():
        return {"ok": False, "class": "key", "message": "还没有密钥。", "next": "先生成一把，再把公钥加到宿主。", "detail": "", "fingerprint": ""}
    result = subprocess.run(
        [
            "ssh", "-v", "-p", str(port), "-o", "BatchMode=yes", "-o", "ConnectTimeout=6",
            "-o", "StrictHostKeyChecking=accept-new", "-o", "IdentitiesOnly=yes", "-i", KEY,
            f"root@{host}", "true",
        ],
        capture_output=True, text=True, timeout=20,
    )
    fingerprint = known_fingerprint(host, port)
    if result.returncode == 0:
        return {"ok": True, "class": "", "message": "连上了。", "next": "", "detail": "", "fingerprint": fingerprint}
    kind, message, following = classify(result.stderr, result.stderr if result.returncode != 0 else "")
    return {
        "ok": False,
        "class": kind,
        "message": message,
        "next": following,
        "detail": (result.stderr or "").strip()[-1500:],
        "fingerprint": fingerprint,
    }


class Handler(BaseHTTPRequestHandler):
    def reply(self, code: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/wonton/api/state":
            cfg = config()
            cfg.update(public_key=public_key(), fingerprint=known_fingerprint(cfg["host"], cfg["port"]))
            self.reply(200, cfg)
        else:
            self.reply(404, {"problem": "not found"})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(length) or b"{}")
        if self.path == "/wonton/api/state":
            cfg = config()
            cfg.update(public_key=public_key(), fingerprint=known_fingerprint(cfg["host"], cfg["port"]))
            return self.reply(200, cfg)
        if self.path == "/wonton/api/config":
            host = str(body.get("host") or "").strip()
            port = int(body.get("port") or 22)
            if not re.fullmatch(r"[A-Za-z0-9.:-]{1,255}", host) or not 0 < port < 65536:
                return self.reply(400, {"problem": "地址或端口不合法"})
            self.reply(200, save_config(host, port))
        elif self.path == "/wonton/api/key/regenerate":
            return self.reply(200, {"public_key": regenerate()})
        elif self.path == "/wonton/api/key/revoke":
            revoke()
            return self.reply(200, {"public_key": ""})
        elif self.path == "/wonton/api/test":
            return self.reply(200, test_connection())
        else:
            self.reply(404, {"problem": "not found"})


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    sys.exit(0)
