#!/bin/sh
# 容器里的第一个进程：备好目录和配置，起 nginx 和 Zellij，等 Zellij 能应答后核对登录令牌，随后守着它。
# 任何一步失败都直接退出，容器跟着不健康，不做兜底。
set -eu

# 宿主决定的 uid 不一定在镜像的 passwd 里，缺了就补一行（名字只影响提示符和 Zellij 的用户名）。
uid="$(id -u)"
gid="$(id -g)"
grep -q "^[^:]*:[^:]*:${uid}:" /etc/passwd ||
    printf 'wonton:x:%s:%s:wonton:%s:/bin/bash\n' "$uid" "$gid" "$HOME" >>/etc/passwd
grep -q "^[^:]*:[^:]*:${gid}:" /etc/group ||
    printf 'wonton:x:%s:\n' "$gid" >>/etc/group

mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# web server 起会话时要一个配置文件路径；只写要改的那一项，其余用 Zellij 自带默认。
config="$XDG_CONFIG_HOME/zellij/config.kdl"
mkdir -p "${config%/*}"
[ -s "$config" ] || printf 'default_shell "/opt/wonton/shell.sh"\n' >"$config"

# 只认核心的地址，别的来源一律 403。核心在插件网络里固定占最后一个可用地址（规范“网络”），
# 由自己网段的广播地址减一算出来，不靠注入变量（没声明 sso: proxy 时没有 WONTON_CORE_ADDRESS）。
cidr="$(ip -4 -o addr show dev eth0 | awk '{print $4; exit}')"
[ -n "$cidr" ] || { echo "eth0 上没有 IPv4 地址" >&2; exit 1; }
IFS=./ read -r a b c d bits <<EOF
$cidr
EOF
mask=$(( (1 << (32 - bits)) - 1 ))
core=$(( (((a << 24) + (b << 16) + (c << 8) + d) & ~mask) + mask - 1 ))
core_ip="$(( (core >> 24) & 255 )).$(( (core >> 16) & 255 )).$(( (core >> 8) & 255 )).$(( core & 255 ))"
sed "s|@CORE@|$core_ip|" /opt/wonton/default.conf.template >/tmp/default.conf

# 先备好令牌、密钥和入口页，健康检查一过页面就是可用的。
/opt/wonton/init.sh

python3 /opt/wonton/server.py &
nginx -e /dev/stderr -g 'daemon off;' &
zellij web --start &
zellij_pid=$!
trap 'kill -TERM "$zellij_pid" 2>/dev/null || true; wait "$zellij_pid" 2>/dev/null || true; exit 0' TERM INT

tries=0
until curl -fsS -o /dev/null http://127.0.0.1:8082/info/version; do
    kill -0 "$zellij_pid" 2>/dev/null || { echo "zellij web 退出了" >&2; exit 1; }
    tries=$((tries + 1))
    [ "$tries" -lt 60 ] || { echo "zellij web 60 秒还没应答" >&2; exit 1; }
    sleep 1
done

# 起来以后核对令牌（可能被吊销过），换了就重填页面。
/opt/wonton/init.sh --revalidate
printf 'authorized key: %s\n' "$(cat "$HOME/.ssh/id_ed25519.pub")"

wait "$zellij_pid"
