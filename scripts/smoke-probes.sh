# shellcheck shell=bash
# 跟着插件走的冒烟探针。网页、身份、数据三项都真的请求插件。

# 入口页出现（没有 Zellij 会话 Cookie 时 / 落到入口页），页面上有登录令牌和 SSH 公钥。
web_assert() { local page; page="$(cat)"; grep -q 'authorized_keys' <<<"$page" && grep -q 'ssh-ed25519' <<<"$page"; }

# 身份就是核心网关：带主人会话能拿到入口页，而页面的令牌是真的能登录的（Zellij 回 200）。
identity_check() {
    local page token
    page="$(web_get /wonton)" || { echo "取入口页失败：$page"; return 1; }
    token="$(sed -n 's#.*id="token" value="\([^"]*\)".*#\1#p' <<<"$page")"
    [[ -n "$token" ]] || { echo "入口页里没有令牌：$(head -c 200 <<<"$page")"; return 1; }
    # 网关只认带会话的同源请求：POST 要带 jar。
    curl -sS --noproxy '*' -b "$SMOKE_JAR" -o /dev/null -f -H 'Content-Type: application/json' \
        -d "{\"auth_token\":\"$token\"}" "${SMOKE_WEB_URL%/}/command/login" ||
        {
            echo "页面里的令牌登录不了 Zellij"
            echo "页面令牌=$token"
            docker exec -u 0 "$(web_container)" sh -c 'printf "文件令牌="; cat /data/state/token; echo; zellij web --list-tokens; printf "页面="; head -c 80 /tmp/landing.html' 2>&1
            curl -sS --noproxy '*' -b "$SMOKE_JAR" -H 'Content-Type: application/json' -d "{\"auth_token\":\"$token\"}" "${SMOKE_WEB_URL%/}/command/login" 2>&1
            return 1
        }
}

# 数据：令牌、SSH 密钥和会话快照都在插件卷里。写一条标记，同时记下当前令牌；重装、升级后都还在才算数。
web_container() { printf 'wonton-%s--dev-zellij-terminal--web' "$SMOKE_INSTANCE"; }

marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
    if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/terminal-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

data_write() {
    local marker
    marker="$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    printf '%s\n' "$marker" >"$(marker_file)"
    docker exec -u 0 "$(web_container)" sh -c "printf %s '$marker' > /data/state/smoke-marker && cat /data/state/token" \
        >>"$(marker_file)" ||
        { echo "写标记失败"; return 1; }
}

data_check() {
    local marker token want
    { read -r marker; read -r token; } <"$(marker_file)"
    want="$(docker exec -u 0 "$(web_container)" cat /data/state/smoke-marker 2>&1)" ||
        { echo "标记读不到：$want"; return 1; }
    [[ "$want" == "$marker" ]] || { echo "标记对不上：$want != $marker"; return 1; }
    [[ -n "$token" ]] || return 0
    docker exec -u 0 "$(web_container)" sh -c 'cat /data/state/token' 2>/dev/null |
        grep -qxF "$token" || { echo "登录令牌变了"; return 1; }
}
