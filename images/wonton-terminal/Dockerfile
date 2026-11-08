# Zellij 官方的网页终端，加一个只监听回环的 nginx 反代：Zellij 的 URL 在根路径，核心网关按子域名转发过来，
# 两边都在容器的同一个网络命名空间里，所以 Zellij 可以只听 127.0.0.1（只听回环就不必给它配 TLS，它自己的规矩是
# 监听别的地址才强制 HTTPS），TLS 在网关和隧道那边。
#
# 镜像自己构建：上游只发二进制，没有官方镜像。二进制按发行页的 sha256 固定，解包后原样放进镜像，不编译、不改源码。
# Zellij 的许可证写在 NOTICE 里。
FROM nginx:1.31.7-alpine@sha256:892bb2152464f0c5d8972593a5f5afaf8054552580b699d95f8ff4af08c2d33d

ARG TARGETARCH
ARG ZELLIJ_VERSION=0.45.1
# 0.45.1 发行页 zellij-<target>-unknown-linux-musl.tar.gz 的摘要，逐架构一份（发行页另有一份 .sha256sum，算的是解包后的二进制，别混用）。
ARG ZELLIJ_SHA256_AMD64=40bcc2e03f5d5ae8e054e39f676081fe12ab70871506996ba595834c3718eefc
ARG ZELLIJ_SHA256_ARM64=05f0802afadd53f8db9514e7cae53c9ae8432fed1b35b8294aa816ee3044a16b

# bash 是 Zellij 里的默认 shell（sh 没有补全和更好的行编辑），openssh-client 给局域网 SSH 用，curl 给入口脚本核对令牌。
RUN apk add --no-cache bash openssh-client curl python3 \
  && case "$TARGETARCH" in \
    amd64) target=x86_64; sha="$ZELLIJ_SHA256_AMD64" ;; \
    arm64) target=aarch64; sha="$ZELLIJ_SHA256_ARM64" ;; \
    *) echo "不支持的架构：$TARGETARCH" >&2; exit 1 ;; \
  esac \
  && file="zellij-${target}-unknown-linux-musl.tar.gz" \
  && curl -fsSL -o "/tmp/$file" \
    "https://github.com/zellij-org/zellij/releases/download/v${ZELLIJ_VERSION}/${file}" \
  && echo "${sha}  /tmp/${file}" | sha256sum -c - \
  && tar -xzf "/tmp/$file" -C /usr/local/bin zellij \
  && chmod 755 /usr/local/bin/zellij \
  && rm "/tmp/$file"

COPY nginx.conf /etc/nginx/nginx.conf
COPY default.conf.template landing.html server.py shell.sh /opt/wonton/
COPY entrypoint.sh init.sh /opt/wonton/
# 容器以宿主上任意 PUID:PGID 跑，Bash 和 Zellij 要按 uid 查用户名：入口脚本临时把这两行补进去，
# 所以镜像里的 passwd 和 group 得让普通用户可写。
RUN chmod 0555 /opt/wonton/entrypoint.sh /opt/wonton/init.sh /opt/wonton/server.py /opt/wonton/shell.sh \
  && chmod 0666 /etc/passwd /etc/group

# 容器以 PUID:PGID 运行，master 进程不是 root，pid 和临时路径放在 /tmp。
ENV HOME=/data/home \
  XDG_DATA_HOME=/data/xdg-data \
  XDG_CACHE_HOME=/data/xdg-cache \
  XDG_CONFIG_HOME=/data/xdg-config \
  XDG_RUNTIME_DIR=/data/run \
  SHELL=/bin/bash

ENTRYPOINT ["/opt/wonton/entrypoint.sh"]
