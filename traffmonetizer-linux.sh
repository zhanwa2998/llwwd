#!/usr/bin/env bash
# One-run TraffMonetizer installer for a personally owned physical home device
# using a residential connection. Do NOT use on VPS/cloud/hosting, servers,
# virtual machines, VPNs, proxies, or devices not exclusively owned by you.
set -Eeuo pipefail

readonly CONTAINER_NAME="traffmonetizer"
readonly IMAGE_BASE="traffmonetizer/cli_v2"
# Token supplied by the user. Keep this file private.
readonly TM_TOKEN='tijdaqg/gZnrl3aer6GemiypCEJhPyyFyGlzm/JIrIA='

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "请用 sudo 运行：sudo bash $0"
[[ -r /etc/os-release ]] || fail "找不到 /etc/os-release，无法识别 Linux 发行版。"
# shellcheck disable=SC1091
. /etc/os-release
OS_ID="${ID:-unknown}"
OS_ID_LIKE="${ID_LIKE:-}"

printf '%s\n' \
  "注意：此程序会把设备作为网络流量出口，第三方请求将经由你的公网 IP。" \
  "TraffMonetizer 官方条款要求住宅 IP，并禁止 VPS、云主机、服务器、VPN 或代理环境。" \
  "请只在你自有的家用实体 Linux 设备/树莓派及住宅网络使用，并遵守当地法律和网络服务条款。"

# Select the official TraffMonetizer Docker tag by CPU architecture.
case "$(uname -m)" in
  x86_64|amd64) image_tag="latest" ;;
  aarch64|arm64) image_tag="arm64v8" ;;
  armv7l) image_tag="arm32v7" ;;
  *) fail "不支持的 CPU 架构：$(uname -m)。官方镜像列出的架构为 x86_64、ARM64、ARMv7。" ;;
esac

# The official Docker convenience installer supports these major distro
# families. It is not universal; unsupported systems must install Docker using
# their distro's documented method first.
if ! command -v docker >/dev/null 2>&1; then
  case "$OS_ID" in
    ubuntu|debian|raspbian|fedora|centos|rhel|rocky) ;;
    *)
      case " $OS_ID_LIKE " in
        *" debian "*|*" ubuntu "*|*" fedora "*|*" rhel "*|*" centos "*|*" rocky "*)
          fail "检测到兼容发行版 '$OS_ID'，但 Docker 官方自动安装脚本不一定支持它。请先按该发行版的 Docker 官方文档安装 Docker Engine，再运行本脚本。"
          ;;
        *) fail "当前发行版 '$OS_ID' 不在 Docker 官方自动安装脚本明确支持的列表中。请先按该发行版的 Docker 官方文档安装 Docker Engine，再运行本脚本。" ;;
      esac
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    case "$OS_ID" in
      ubuntu|debian|raspbian)
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
        ;;
      fedora|centos|rhel|rocky)
        if command -v dnf >/dev/null 2>&1; then
          dnf install -y ca-certificates curl
        elif command -v yum >/dev/null 2>&1; then
          yum install -y ca-certificates curl
        else
          fail "找不到 dnf/yum，无法自动安装 curl。"
        fi
        ;;
    esac
  fi

  installer="$(mktemp /tmp/docker-install.XXXXXX.sh)"
  trap 'rm -f "$installer"' EXIT
  printf '%s\n' "正在下载 Docker 官方安装脚本（仅支持官方列出的主流发行版）……"
  curl -fsSL --proto '=https' --tlsv1.2 https://get.docker.com -o "$installer" \
    || fail "下载 Docker 官方安装脚本失败。"
  grep -Fq 'Docker Engine for Linux installation script.' "$installer" \
    || fail "下载内容不像 Docker 官方安装脚本，已停止。"
  printf '%s\n' "正在安装 Docker Engine 及依赖；这会添加 Docker 软件源并安装/更新相关软件包……"
  sh "$installer"
  rm -f "$installer"
  trap - EXIT
fi

# Ensure the daemon is running where systemd/service management exists.
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now docker.service || true
elif command -v service >/dev/null 2>&1; then
  service docker start || true
fi
docker info >/dev/null 2>&1 || fail "Docker 已安装但服务未运行；请启动 Docker Engine 后重新运行脚本。"

image="${IMAGE_BASE}:${image_tag}"
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  state="$(docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)"
  if [[ "$state" == "true" ]]; then
    printf '容器 %s 已在运行，未做更改。\n' "$CONTAINER_NAME"
  else
    printf '容器 %s 已存在但已停止，正在启动它。\n' "$CONTAINER_NAME"
    docker start "$CONTAINER_NAME"
  fi
  printf '查看日志：sudo docker logs --tail 50 -f %s\n' "$CONTAINER_NAME"
  exit 0
fi

printf '正在拉取 TraffMonetizer 官方镜像：%s\n' "$image"
docker pull "$image"
printf '正在创建并启动容器……\n'
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  "$image" start accept --token "$TM_TOKEN"

printf '\n安装完成。\n'
printf '查看状态：sudo docker ps --filter name=^/%s$\n' "$CONTAINER_NAME"
printf '查看日志：sudo docker logs --tail 50 -f %s\n' "$CONTAINER_NAME"
printf '停止服务：sudo docker stop %s\n' "$CONTAINER_NAME"
printf '重新启动：sudo docker start %s\n' "$CONTAINER_NAME"
printf '卸载容器：sudo docker rm -f %s\n' "$CONTAINER_NAME"
printf '\n令牌已写在本脚本中，并作为容器启动参数保存；拥有 root/Docker 管理权限的人可以读取。请勿公开脚本。\n'
printf '此一键脚本自动安装 Docker 的范围限于 Docker 官方安装器支持的主流发行版；并非所有 Linux 变种/版本都受支持。\n'
