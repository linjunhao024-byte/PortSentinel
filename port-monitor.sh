#!/bin/bash

# 端口安全监控 - 一体化管理脚本 v1.0.2

PORTMONITOR_VERSION="1.0.2"

# ── 启动依赖检测 ─────────────────────────────────────────────

_check_deps() {
    local missing=()

    [ "$(uname -s)" != "Linux" ] && printf '%b\n' "\033[0;31m[✗]\033[0m 仅支持 Linux 系统 [当前: $(uname -s)]" && exit 1

    [ -z "$BASH_VERSION" ] && printf '%b\n' "\033[0;31m[✗]\033[0m 需要 bash 环境" && exit 1
    local bash_major="${BASH_VERSINFO[0]}"
    [ "$bash_major" -lt 4 ] && printf '%b\n' "\033[0;31m[✗]\033[0m 需要 bash 4.0+[当前: ${BASH_VERSION}]" && exit 1

    for cmd in python3 systemctl sqlite3 curl awk sed grep tr openssl; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ! command -v iptables &>/dev/null && ! command -v firewall-cmd &>/dev/null && ! command -v nft &>/dev/null; then
        missing+=("iptables/firewalld/nftables [任一]")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        printf '%b\n' "\033[0;31m[✗]\033[0m 缺少必要依赖:"
        for m in "${missing[@]}"; do
            printf '%b\n' "  • $m"
        done
        echo ""
        printf '%b\n' "\033[1;33m安装参考:\033[0m"
        echo "  Debian/Ubuntu:  apt install python3 sqlite3 curl iptables openssl"
        echo "  CentOS/RHEL:    yum install python3 sqlite curl iptables"
        echo "  Arch:           pacman -S python sqlite curl iptables"
        exit 1
    fi
}

if [[ "${1:-}" != "--version" && "${1:-}" != "-v" ]]; then
    _check_deps
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/port-monitor"
DATA_DIR="/var/lib/port-monitor"
LOG_DIR="/var/log/port-monitor"
SERVICE_NAME="port-monitor"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SHORTCUT_FILE="${CONFIG_DIR}/.shortcut_name"

_ROLLBACK_ITEMS=()

_install_rollback() {
    printf '%b\n' "\n${RED}[✗] 安装中断，正在回滚...${NC}"
    local protected_dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")
    for item in "${_ROLLBACK_ITEMS[@]}"; do
        local is_protected=false
        for pd in "${protected_dirs[@]}"; do
            [ "$item" = "$pd" ] && is_protected=true && break
        done
        [ "$is_protected" = true ] && continue
        rm -rf "$item" 2>/dev/null || true
    done
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    printf '%b\n' "${YELLOW}[!] 已清理安装残留${NC}"
    exit 1
}

print_banner() {
    clear
    printf '%b\n' "${BLUE}${BOLD}"
    printf '%s\n' "╔═══════════════════════════════════════════════════════════════╗"
    printf '%s\n' "║                                                               ║"
    printf '%s\n' "║            端口安全监控管理系统                               ║"
    printf '%s\n' "║                                                               ║"
    printf '%s\n' "║       检测端口扫描 | 防御暴力破解 | 自动封禁攻击IP           ║"
    printf '%s\n' "║                                                               ║"
    printf '%s\n' "╚═══════════════════════════════════════════════════════════════╝"
    printf '%b\n' "${NC}"
}

print_step() {
    printf '%b\n' "\n${CYAN}━━━ $1 ━━━${NC}\n"
}

info() { printf '%b\n' "${GREEN}[✓]${NC} $1" >&2; return 0; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $1" >&2; return 0; }
error() { printf '%b\n' "${RED}[✗]${NC} $1" >&2; return 0; }

# 必填输入：不允许空值
ask() {
    local prompt="$1" default="$2"
    local input=""
    while true; do
        if [ -n "$default" ]; then
            printf '%b' "${YELLOW}${prompt} [${default}]: ${NC}" >&2
        else
            printf '%b' "${YELLOW}${prompt}: ${NC}" >&2
        fi
        read -r input
        if [ -n "$input" ]; then
            echo "$input"
            return
        elif [ -n "$default" ]; then
            echo "$default"
            return
        fi
        error "此项不能为空，请重新输入" >&2
    done
}

# 可选输入：允许空值
ask_optional() {
    local prompt="$1" default="$2"
    local input=""
    if [ -n "$default" ]; then
        printf '%b' "${YELLOW}${prompt} [${default}]: ${NC}" >&2
    else
        printf '%b' "${YELLOW}${prompt}: ${NC}" >&2
    fi
    read -r input
    echo "${input:-$default}"
}

ask_yn() {
    local prompt="$1" default="${2:-n}"
    local input=""
    while true; do
        printf '%b' "${YELLOW}${prompt} [$([ "$default" = "y" ] && echo "Y/n" || echo "y/N")]: ${NC}" >&2
        read -r input
        input=$(echo "${input:-$default}" | tr '[:upper:]' '[:lower:]')
        [[ "$input" =~ ^[yn]$ ]] && echo "$input" && return
        error "请输入 y 或 n" >&2
    done
}

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    local choice=""
    printf '%b\n' "${YELLOW}${prompt}${NC}" >&2
    for i in "${!options[@]}"; do
        printf '%b\n' "  ${CYAN}[$((i+1))]${NC} ${options[$i]}" >&2
    done
    while true; do
        printf '%b' "${GREEN}请选择 [1-${count}]: ${NC}" >&2
        read -r choice
        choice="${choice:-1}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            echo "$choice"
            return
        fi
        error "请输入 1-${count} 之间的数字" >&2
    done
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "需要root权限，请使用: sudo $0"
        exit 1
    fi
}

# 判断是否为 IPv6 地址（含冒号即为 IPv6）
_is_ipv6() {
    [[ "$1" == *:* ]]
}

# 统一 IP/CIDR 验证：支持 IPv4、IPv6 和 CIDR 格式
_validate_ip() {
    local ip="$1"
    # 去除 CIDR 前缀进行验证
    local addr="${ip%/*}"
    if _is_ipv6 "$addr"; then
        # IPv6：验证十六进制和冒号组成
        [[ "$addr" =~ ^[0-9a-fA-F:]+$ ]] || return 1
        [[ "$addr" != *":::"* ]] || return 1
        # 计算冒号数量，判断组数
        local colons="${addr//[^:]}"
        local colon_count=${#colons}
        if [[ "$addr" == *"::"* ]]; then
            # 压缩格式：最多 7 个冒号
            [ "$colon_count" -le 7 ] || return 1
            # :: 最多出现一次
            local tmp="${addr/::/}"
            [[ "$tmp" != *"::"* ]] || return 1
        else
            # 完整格式：必须恰好 7 个冒号（8 组）
            [ "$colon_count" -eq 7 ] || return 1
        fi
        # 检查每组最多 4 个十六进制数字
        local IFS=':'
        for group in $addr; do
            [ ${#group} -le 4 ] || return 1
        done
        return 0
    else
        # IPv4：严格验证，拒绝前导零
        printf '%s\n' "$addr" | grep -qE '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
    fi
}

# 端口 → 服务名映射（常见端口）
_port_service() {
    local port="$1"
    case "$port" in
        20) echo "FTP-Data" ;; 21) echo "FTP" ;; 22) echo "SSH" ;; 23) echo "Telnet" ;;
        25) echo "SMTP" ;; 53) echo "DNS" ;; 80) echo "HTTP" ;; 110) echo "POP3" ;;
        143) echo "IMAP" ;; 443) echo "HTTPS" ;; 445) echo "SMB" ;; 465) echo "SMTPS" ;;
        587) echo "SMTP-Sub" ;; 993) echo "IMAPS" ;; 995) echo "POP3S" ;;
        1433) echo "MSSQL" ;; 1521) echo "Oracle" ;; 3306) echo "MySQL" ;;
        3389) echo "RDP" ;; 5432) echo "PostgreSQL" ;; 5900) echo "VNC" ;;
        6379) echo "Redis" ;; 6443) echo "K8s-API" ;; 8080) echo "HTTP-Alt" ;;
        8443) echo "HTTPS-Alt" ;; 8888) echo "HTTP-Alt2" ;; 9090) echo "Prometheus" ;;
        9200) echo "ES" ;; 11211) echo "Memcached" ;; 27017) echo "MongoDB" ;;
        *) echo "" ;;
    esac
}

# 优先读配置，读不到则自动检测防火墙类型
get_firewall_backend() {
    local backend=""
    if [ -f "$CONFIG_FILE" ]; then
        backend=$(grep -A1 '^ban:' "$CONFIG_FILE" 2>/dev/null | grep 'method:' | awk '{print $2}' | tr -d '"' || true)
    fi
    if [ -z "$backend" ] || [ "$backend" = "none" ]; then
        if command -v nft &>/dev/null && nft list ruleset &>/dev/null 2>&1; then
            echo "nftables"
        elif command -v firewall-cmd &>/dev/null && firewall-cmd --state &>/dev/null 2>&1; then
            echo "firewalld"
        elif command -v iptables &>/dev/null; then
            echo "iptables"
        else
            echo "未知"
        fi
    else
        echo "$backend"
    fi
}

do_install() {
    print_banner
    printf '%b\n' "${CYAN}${BOLD}安装向导${NC} - 4 步完成部署\n"

    check_root

    if [ ! -f "./port-monitor" ]; then
        error "未找到 port-monitor 可执行文件"
        printf '%b\n' "${YELLOW}请从 GitHub 下载:${NC}"
        printf '%b\n' "  wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor"
        exit 1
    fi

    set -e
    trap '_install_rollback' ERR INT TERM
    SHORTCUT="pm"

    # ── 步骤 1: 服务器环境 ──
    print_step "步骤 1/4: 服务器环境"
    printf '%b\n' "  ${YELLOW}[1]${NC} 云服务器 - 自动忽略内网流量，避免误报"
    printf '%b\n' "  ${YELLOW}[2]${NC} 独立服务器/VPS - 监控全部流量"
    echo ""
    local env_choice
    env_choice=$(ask_choice "请选择" "云服务器 [阿里云/腾讯云/华为云]" "独立服务器/VPS")
    case $env_choice in
        1) MONITOR_MODE="cloud"; IGNORE_INTERNAL="y" ;;
        2) MONITOR_MODE="standalone"; IGNORE_INTERNAL="n" ;;
    esac

    BAN_METHOD="iptables"
    ENABLE_AUTO_BAN="y"
    SCAN_BAN_DURATION="1h"
    BRUTE_BAN_DURATION="24h"
    SCAN_THRESHOLD=20
    BRUTE_THRESHOLD=5
    SSH_PORT="22"
    ADMIN_IP=""
    info "服务器环境: ${MONITOR_MODE}"

    # ── 步骤 2: 告警通道 ──
    print_step "步骤 2/4: 告警通道"
    ENABLE_TELEGRAM="n"
    ENABLE_DINGTALK="n"
    ENABLE_EMAIL="n"
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    DINGTALK_WEBHOOK=""
    DINGTALK_SECRET=""
    EMAIL_HOST=""
    EMAIL_PORT="465"
    EMAIL_USER=""
    EMAIL_PASS=""
    EMAIL_TO=""

    if [ "$(ask_yn "是否配置告警通知？" "y")" = "y" ]; then
        printf '%b\n' "  ${YELLOW}[1]${NC} Telegram"
        printf '%b\n' "  ${YELLOW}[2]${NC} 钉钉"
        printf '%b\n' "  ${YELLOW}[3]${NC} 邮件"
        printf '%b\n' "  ${YELLOW}[4]${NC} 全部"
        echo ""
        local alert_choice
        alert_choice=$(ask_choice "选择告警通道" "Telegram" "钉钉" "邮件" "全部配置")

        _setup_telegram() {
            ENABLE_TELEGRAM="y"
            while true; do
                TELEGRAM_BOT_TOKEN=$(ask "机器人 Token")
                TELEGRAM_CHAT_ID=$(ask "聊天 ID")
                printf '%b\n' "${CYAN}验证中...${NC}" >&2
                local tg_resp
                tg_resp=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                    -d chat_id="$TELEGRAM_CHAT_ID" \
                    -d text="🧪 PortSentinel 告警测试" \
                    --connect-timeout 10 --max-time 15 2>&1)
                if echo "$tg_resp" | grep -q '"ok":true'; then
                    info "Telegram 验证成功"
                    return
                else
                    error "发送失败: $(echo "$tg_resp" | grep -o '"description":"[^"]*"' || echo "$tg_resp")"
                    [ "$(ask_yn "重新输入？" "y")" != "y" ] && ENABLE_TELEGRAM="n" && warn "已跳过" && return
                fi
            done
        }

        _setup_dingtalk() {
            ENABLE_DINGTALK="y"
            while true; do
                DINGTALK_WEBHOOK=$(ask "Webhook 地址")
                DINGTALK_SECRET=$(ask_optional "签名密钥 [可选]" "")
                printf '%b\n' "${CYAN}验证中...${NC}" >&2
                local ding_url="$DINGTALK_WEBHOOK"
                if [ -n "$DINGTALK_SECRET" ]; then
                    local ts_ms sign_str sign
                    ts_ms=$(date +%s%3N)
                    sign_str="${ts_ms}\n${DINGTALK_SECRET}"
                    sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64 | sed 's/+/%2B/g;s/\//%2F/g;s/=/%3D/g')
                    ding_url="${DINGTALK_WEBHOOK}&timestamp=${ts_ms}&sign=${sign}"
                fi
                local ding_resp
                ding_resp=$(curl -s -X POST "$ding_url" \
                    -H 'Content-Type: application/json' \
                    -d '{"msgtype":"text","text":{"content":"🧪 PortSentinel 告警测试"}}' \
                    --connect-timeout 10 --max-time 15 2>&1)
                if echo "$ding_resp" | grep -q '"errcode":0'; then
                    info "钉钉验证成功"
                    return
                else
                    error "发送失败: $ding_resp"
                    [ "$(ask_yn "重新输入？" "y")" != "y" ] && ENABLE_DINGTALK="n" && warn "已跳过" && return
                fi
            done
        }

        _setup_email() {
            ENABLE_EMAIL="y"
            while true; do
                local provider
                provider=$(ask_choice "邮件服务商" "QQ邮箱" "163邮箱" "谷歌邮箱" "自定义")
                case $provider in
                    1) EMAIL_HOST="smtp.qq.com"; EMAIL_PORT="465" ;;
                    2) EMAIL_HOST="smtp.163.com"; EMAIL_PORT="465" ;;
                    3) EMAIL_HOST="smtp.gmail.com"; EMAIL_PORT="587" ;;
                    4) EMAIL_HOST=$(ask "SMTP服务器"); EMAIL_PORT=$(ask "端口" "465") ;;
                esac
                EMAIL_USER=$(ask "发件人邮箱")
                EMAIL_PASS=$(ask "密码/授权码")
                EMAIL_TO=$(ask "收件人邮箱")
                printf '%b\n' "${CYAN}验证中...${NC}" >&2
                local curl_proto="smtp"
                [ "$EMAIL_PORT" = "465" ] && curl_proto="smtps"
                local mail_resp curl_exit=0
                mail_resp=$(printf '%b\n' "Subject: PortSentinel 告警测试\nContent-Type: text/plain; charset=UTF-8\n\n🧪 PortSentinel 告警测试" | \
                    curl -s --url "${curl_proto}://${EMAIL_HOST}:${EMAIL_PORT}" \
                    --ssl-reqd --mail-from "$EMAIL_USER" --mail-rcpt "$EMAIL_TO" \
                    --user "${EMAIL_USER}:${EMAIL_PASS}" \
                    --connect-timeout 10 --max-time 15 -T - 2>&1) || curl_exit=$?
                if [ "$curl_exit" -eq 0 ] && ! echo "$mail_resp" | grep -qi 'denied\|535\|550\|553'; then
                    info "邮件验证成功"
                    return
                else
                    error "发送失败: ${mail_resp:-curl 退出码 $curl_exit}"
                    [ "$(ask_yn "重新输入？" "y")" != "y" ] && ENABLE_EMAIL="n" && warn "已跳过" && return
                fi
            done
        }

        case $alert_choice in
            1) _setup_telegram ;;
            2) _setup_dingtalk ;;
            3) _setup_email ;;
            4) _setup_telegram; _setup_dingtalk; _setup_email ;;
        esac
    else
        info "已跳过告警配置"
    fi

    # ── 步骤 3: 检测规则 ──
    print_step "步骤 3/4: 检测规则"
    printf '%b\n' "  ${YELLOW}[1]${NC} 严格 - 10端口/10秒, 3次SSH/分钟"
    printf '%b\n' "  ${YELLOW}[2]${NC} 正常 - 20端口/10秒, 5次SSH/分钟 [推荐]"
    printf '%b\n' "  ${YELLOW}[3]${NC} 宽松 - 50端口/10秒, 10次SSH/分钟"
    echo ""
    local sensitivity
    sensitivity=$(ask_choice "检测灵敏度" "严格" "正常 [推荐]" "宽松")
    case $sensitivity in
        1) SCAN_THRESHOLD=10; BRUTE_THRESHOLD=3 ;;
        2) SCAN_THRESHOLD=20; BRUTE_THRESHOLD=5 ;;
        3) SCAN_THRESHOLD=50; BRUTE_THRESHOLD=10 ;;
    esac
    info "灵敏度: 端口扫描=${SCAN_THRESHOLD}/10s, SSH暴破=${BRUTE_THRESHOLD}/min"

    # ── 步骤 4: 确认安装 ──
    print_step "步骤 4/4: 确认安装"
    printf '%b\n' "  服务器: $([ "$MONITOR_MODE" = "cloud" ] && printf '%b\n' "${GREEN}云服务器${NC}" || printf '%b\n' "${GREEN}独立服务器${NC}")"
    printf '%b\n' "  告警: $([ "$ENABLE_TELEGRAM" = "y" ] && echo -n "TG " ; [ "$ENABLE_DINGTALK" = "y" ] && echo -n "钉钉 " ; [ "$ENABLE_EMAIL" = "y" ] && echo -n "邮件 " ; [ "$ENABLE_TELEGRAM" = "n" ] && [ "$ENABLE_DINGTALK" = "n" ] && [ "$ENABLE_EMAIL" = "n" ] && echo -n "未配置")"
    echo ""
    [ "$(ask_yn "确认安装？" "y")" != "y" ] && warn "已取消" && trap - ERR INT TERM && set +e && exit 0

    printf '%b\n' "\n${CYAN}正在部署...${NC}"

    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    _ROLLBACK_ITEMS+=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")
    install -m 755 ./port-monitor "$INSTALL_DIR/port-monitor"
    _ROLLBACK_ITEMS+=("$INSTALL_DIR/port-monitor")
    generate_config
    chmod 600 "$CONFIG_FILE"
    _ROLLBACK_ITEMS+=("$CONFIG_FILE")
    echo "$SHORTCUT" > "$SHORTCUT_FILE"
    create_service
    _ROLLBACK_ITEMS+=("/etc/systemd/system/${SERVICE_NAME}.service")
    create_logrotate
    cp "$0" "/usr/local/bin/port-monitor-ctl"
    chmod +x "/usr/local/bin/port-monitor-ctl"
    ln -sf "/usr/local/bin/port-monitor-ctl" "/usr/local/bin/${SHORTCUT}"
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    trap - ERR INT TERM
    set +e
    info "部署完成"

    echo ""
    printf '%b\n' "  ${GREEN}快捷命令:${NC} pm"
    printf '%b\n' "  ${GREEN}使用方法:${NC} 终端输入 pm 即可打开管理面板"
    echo ""

    if [ "$(ask_yn "现在启动服务？" "y")" = "y" ]; then
        if systemctl start "$SERVICE_NAME" 2>&1; then
            info "服务已启动"
        else
            error "启动失败，查看日志: journalctl -u $SERVICE_NAME -n 10 --no-pager"
        fi
    fi

    echo ""
    [ "$(ask_yn "进入管理面板？" "y")" = "y" ] && show_menu_loop
}

# YAML 安全转义：对可能含特殊字符的值进行转义，防止解析器崩溃
_yaml_escape() {
    local val="$1"
    # 先转义反斜杠，再转义双引号
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    echo "$val"
}

generate_config() {
    # permanent 映射为 87600h，引擎侧应根据 permanent 字段走独立封禁逻辑
    local brute_ban_display="$BRUTE_BAN_DURATION"
    if [ "$BRUTE_BAN_DURATION" = "permanent" ]; then
        brute_ban_display="87600h"
    fi

    cat > "$CONFIG_FILE" << EOF
# 端口安全监控配置 v${PORTMONITOR_VERSION}

monitor:
  interval: 5s
  ports: "1-65535"
  protocol: "tcp"

rules:
  port_scan:
    window: 10s
    thresholds:
      low: $((SCAN_THRESHOLD / 2))
      medium: $SCAN_THRESHOLD
      high: $((SCAN_THRESHOLD * 5))
      critical: $((SCAN_THRESHOLD * 50))
    auto_ban: $([ "$ENABLE_AUTO_BAN" = "y" ] && echo "true" || echo "false")
    ban_duration: ${SCAN_BAN_DURATION:-1h}

  brute_force:
    window: 60s
    auto_ban: $([ "$ENABLE_AUTO_BAN" = "y" ] && echo "true" || echo "false")
    ban_duration: ${brute_ban_display:-24h}
    permanent: $([ "$BRUTE_BAN_DURATION" = "permanent" ] && echo "true" || echo "false")
    sensitive_ports:
      - port: ${SSH_PORT:-22}
        name: "SSH"
        threshold: $BRUTE_THRESHOLD
      - port: 3306
        name: "MySQL"
        threshold: 10
      - port: 6379
        name: "Redis"
        threshold: 3

  ddos:
    window: 5s
    threshold: 1000
    auto_ban: $([ "$ENABLE_AUTO_BAN" = "y" ] && echo "true" || echo "false")
    ban_duration: 1h

  # 自适应阈值：学习期采集流量基线，动态调整检测灵敏度
  # 适用于流量波动大的环境，可减少误报
  adaptive:
    enabled: false
    learning_period: 30m     # 学习期时长
    multiplier: 3.0          # 阈值 = 基线均值 × 倍率（越大越宽松）
    anomaly_factor: 10.0     # 流量突增倍率告警
    recalibrate_interval: 1h # 重新校准间隔

# 蜜罐端口：任何连接这些端口的 IP 将被立即封禁（零容忍）
honeypot:
  enabled: false
  ports:
    - 2222
    - 8888
    - 33899
  ban_duration: 7d
  permanent: false

# 轻量 HTTP API 接口（可选）
api:
  enabled: false
  host: "127.0.0.1"       # 监听地址（生产环境建议 127.0.0.1）
  port: 8900              # 监听端口
  token: ""               # API Token（空=无认证，生产环境务必设置）

# 分布式联动（可选）：多节点共享封禁列表
# 需要对端节点启用 API 服务
federation:
  enabled: false
  sync_interval: 60s       # 同步间隔
  node_id: ""              # 节点标识（留空使用 hostname）
  cluster_secret: ""       # 集群共享密钥
  peers:
    # - url: "http://10.0.0.2:8900"
    #   token: "peer-token"

# 威胁情报集成
threat_intel:
  enabled: false
  abuseipdb_key: ""        # AbuseIPDB API Key
  sync_interval: 6h

# 攻击行为关联分析
correlation:
  enabled: false
  window: 10m

# 自定义响应动作
response:
  enabled: false
  actions: []

alert:
  telegram:
    enabled: $([ "$ENABLE_TELEGRAM" = "y" ] && echo "true" || echo "false")
    bot_token: "$(_yaml_escape "$TELEGRAM_BOT_TOKEN")"
    chat_id: "$(_yaml_escape "$TELEGRAM_CHAT_ID")"

  dingtalk:
    enabled: $([ "$ENABLE_DINGTALK" = "y" ] && echo "true" || echo "false")
    webhook: "$(_yaml_escape "$DINGTALK_WEBHOOK")"
    secret: "$(_yaml_escape "$DINGTALK_SECRET")"

  email:
    enabled: $([ "$ENABLE_EMAIL" = "y" ] && echo "true" || echo "false")
    smtp_host: "$EMAIL_HOST"
    smtp_port: ${EMAIL_PORT:-465}
    username: "$(_yaml_escape "$EMAIL_USER")"
    password: "$(_yaml_escape "$EMAIL_PASS")"
    to: "$(_yaml_escape "$EMAIL_TO")"

  wechat:
    enabled: false
    webhook: ""

  feishu:
    enabled: false
    webhook: ""
    secret: ""

  slack:
    enabled: false
    webhook: ""

  log:
    enabled: true
    path: "${LOG_DIR}/port-monitor.log"

  # 告警模板（可选，注释则使用内置默认模板）
  # 可用变量: {{src_ip}} {{attack_type}} {{dst_port}} {{count}} {{window}}
  #           {{level}} {{duration}} {{time}} {{hostname}} {{service_name}}
  # templates:
  #   ban: "🚨 自动封禁 | {{src_ip}} | {{attack_type}} | :{{dst_port}} | {{duration}}"
  #   port_scan: "🚨 端口扫描 [{{level}}] from {{src_ip}} | {{count}} ports/{{window}}s"
  #   brute_force: "🚨 {{service_name}} 暴力破解 | {{src_ip}} | {{count}} attempts/{{window}}s"
  #   ddos: "🚨 DDoS | {{src_ip}} | {{count}} SYN/{{window}}s"

storage:
  type: "both"
  memory:
    max_items: 100000
    ttl: 1h
  sqlite:
    path: "${DATA_DIR}/monitor.db"

ban:
  method: "$BAN_METHOD"
  # mode: "drop"       # drop=直接丢弃 | reject=拒绝并回复 | rate_limit=限速（允许低频访问）
  whitelist:
    - "127.0.0.1"
    - "::1"
$([ -n "$ADMIN_IP" ] && echo "    - \"$ADMIN_IP\"")
$([ "$IGNORE_INTERNAL" = "y" ] && cat << 'WHITELIST'
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "169.254.0.0/16"
    - "fe80::/10"
    - "fc00::/7"
WHITELIST
)
EOF
}

create_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Port Security Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$DATA_DIR
ExecStart=$INSTALL_DIR/port-monitor -config $CONFIG_FILE
Restart=always
RestartSec=5
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF
}

create_logrotate() {
    cat > "/etc/logrotate.d/port-monitor" << EOF
${LOG_DIR}/port-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    copytruncate
    missingok
    notifempty
    create 640 root root
}
EOF
}

do_update() {
    check_root
    print_banner

    if [ ! -f "./port-monitor" ]; then
        error "当前目录未找到 port-monitor 可执行文件"
        printf '%b\n' "${YELLOW}请将新版 port-monitor 放到当前目录后重试${NC}"
        exit 1
    fi

    if [ ! -f "$INSTALL_DIR/port-monitor" ]; then
        error "PortSentinel 尚未安装，请先执行安装"
        exit 1
    fi

    printf '%b\n' "${CYAN}将更新 PortSentinel 程序文件[配置和数据保留不变]${NC}\n"

    local backup="/tmp/port-monitor.bak.$(date +%s)"
    cp "$INSTALL_DIR/port-monitor" "$backup"
    info "已备份旧版本到 $backup"

    # 原子替换：先删后写，避免 Text file busy 错误
    rm -f "$INSTALL_DIR/port-monitor"
    install -m 755 ./port-monitor "$INSTALL_DIR/port-monitor"
    info "程序文件已更新"

    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        if systemctl restart "$SERVICE_NAME" 2>&1; then
            info "服务已重启"
        else
            error "重启失败: journalctl -u $SERVICE_NAME -n 5 --no-pager"
        fi
    else
        warn "服务当前未运行，跳过重启"
    fi

    echo ""
    info "更新完成"
}

do_uninstall() {
    check_root
    printf '%b\n' "${RED}警告: 将卸载服务[保留配置和数据]${NC}"
    if [ "$(ask_yn "确定卸载？" "n")" != "y" ]; then return; fi

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    rm -f "$INSTALL_DIR/port-monitor"
    rm -f "/usr/local/bin/port-monitor-ctl"

    # 读取安装时持久化的快捷命令名精确删除
    if [ -f "$SHORTCUT_FILE" ]; then
        local saved_shortcut
        saved_shortcut=$(cat "$SHORTCUT_FILE")
        rm -f "/usr/local/bin/$saved_shortcut"
        info "已删除快捷命令: $saved_shortcut"
        rm -f "$SHORTCUT_FILE"
    else
        for cmd in pm pmon psm psmon portmon; do
            rm -f "/usr/local/bin/$cmd"
        done
    fi

    systemctl daemon-reload
    info "卸载完成[配置保留在 $CONFIG_DIR]"
}

do_full_uninstall() {
    check_root
    printf '%b\n' "${RED}警告: 将删除所有文件，包括配置和数据！${NC}"
    if [ "$(ask_yn "确定完全卸载？" "n")" != "y" ]; then return; fi

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    rm -f "$INSTALL_DIR/port-monitor"
    rm -f "/usr/local/bin/port-monitor-ctl"

    if [ -f "$SHORTCUT_FILE" ]; then
        local saved_shortcut
        saved_shortcut=$(cat "$SHORTCUT_FILE")
        rm -f "/usr/local/bin/$saved_shortcut"
        rm -f "$SHORTCUT_FILE"
    else
        for cmd in pm pmon psm psmon portmon; do
            rm -f "/usr/local/bin/$cmd"
        done
    fi

    rm -f "/etc/logrotate.d/port-monitor"
    rm -rf "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    systemctl daemon-reload
    info "完全卸载完成"
}

do_start() {
    check_root
    if systemctl start "$SERVICE_NAME" 2>&1; then
        info "服务已启动"
    else
        error "启动失败: journalctl -u $SERVICE_NAME -n 5 --no-pager"
    fi
}

do_stop() {
    check_root
    if systemctl stop "$SERVICE_NAME" 2>&1; then
        info "服务已停止"
    else
        error "停止失败"
    fi
}

do_restart() {
    check_root
    if systemctl restart "$SERVICE_NAME" 2>&1; then
        info "服务已重启"
    else
        error "重启失败: journalctl -u $SERVICE_NAME -n 5 --no-pager"
    fi
}

do_status() {
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || warn "服务未安装"
}

do_logs() {
    printf '%b\n' "${YELLOW}按 Ctrl+C 退出${NC}"
    journalctl -u "$SERVICE_NAME" -f --no-pager || true
}

do_reload() {
    check_root
    if ! systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        error "服务未运行，请先启动"
        return 1
    fi
    local pid
    pid=$(pgrep -x "port-monitor" || true)
    if [ -z "$pid" ]; then
        error "未找到 port-monitor 进程"
        return 1
    fi
    kill -HUP "$pid" 2>/dev/null
    if [ $? -eq 0 ]; then
        info "已发送 SIGHUP，配置热加载中..."
        sleep 1
        # 检查进程是否仍在运行（热加载不应导致退出）
        if kill -0 "$pid" 2>/dev/null; then
            info "热加载完成，服务运行正常 [PID: $pid]"
        else
            error "热加载后进程退出，请检查配置和日志"
        fi
    else
        error "发送信号失败"
    fi
}

do_edit_config() {
    check_root
    ${EDITOR:-vi} "$CONFIG_FILE" || true
    if [ "$(ask_yn "热加载配置？(选否则重启服务)" "y")" = "y" ]; then
        do_reload
    else
        do_restart
    fi
}

do_view_bans() {
    check_root
    local backend
    backend=$(get_firewall_backend)
    printf '%b\n' "${CYAN}当前封禁的IP (${backend}):${NC}"

    local ips=""
    case "$backend" in
        iptables)
            ips=$(iptables -L INPUT -n 2>/dev/null | grep DROP | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
            ips+=$'\n'$(ip6tables -L INPUT -n 2>/dev/null | grep DROP | grep -oE '([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}' || true)
            ;;
        firewalld)
            ips=$(firewall-cmd --list-rich-rules 2>/dev/null | grep -oP "address='\\K[^']+" || true)
            ;;
        nftables)
            ips=$(nft list ruleset 2>/dev/null | grep -oP '(?:ip|ip6) saddr \K\S+' || true)
            ;;
        *)
            warn "无法检测防火墙后端，请手动检查"
            return
            ;;
    esac

    if [ -z "$ips" ]; then
        printf '%b\n' "${YELLOW}暂无封禁${NC}"
    else
        echo "$ips" | sort -u | while read -r ip; do printf '%b\n' "  ${RED}$ip${NC}"; done
    fi
}

do_unban() {
    check_root
    local ip
    ip=$(ask "要解封的IP")
    if _validate_ip "$ip"; then
        local backend
        backend=$(get_firewall_backend)
        local v6=false
        _is_ipv6 "$ip" && v6=true
        case "$backend" in
            iptables)
                local cmd="iptables"
                $v6 && cmd="ip6tables"
                $cmd -D INPUT -s "$ip" -j DROP 2>/dev/null && info "已解封 $ip" || warn "IP不在封禁列表"
                ;;
            firewalld)
                local family="ipv4"
                $v6 && family="ipv6"
                firewall-cmd --remove-rich-rule="rule family='$family' source address='$ip' reject" --permanent 2>/dev/null \
                    && firewall-cmd --reload 2>/dev/null \
                    && info "已解封 $ip" \
                    || warn "IP不在封禁列表"
                ;;
            nftables)
                local addr_type="ip"
                $v6 && addr_type="ip6"
                nft delete rule inet filter input $addr_type saddr "$ip" drop 2>/dev/null \
                    && info "已解封 $ip" \
                    || warn "IP不在封禁列表"
                ;;
            *)
                error "未知防火墙后端，请手动解封"
                ;;
        esac
    else
        error "IP格式不正确"
    fi
}

# ── 白名单管理 ─────────────────────────────────────────────────

_get_whitelist() {
    # 从配置文件提取白名单条目（去除引号和前导空格）
    if [ ! -f "$CONFIG_FILE" ]; then
        return
    fi
    # 提取 ban: 段下的 whitelist 列表
    sed -n '/^ban:/,/^[a-z]/p' "$CONFIG_FILE" 2>/dev/null \
        | grep '^\s*-\s*"' \
        | sed 's/^\s*-\s*"//; s/"\s*$//' \
        | grep -v '^$'
}

_add_whitelist_entry() {
    local entry="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在"
        return 1
    fi
    # 检查是否已存在
    if grep -qF "\"$entry\"" "$CONFIG_FILE" 2>/dev/null; then
        warn "$entry 已在白名单中"
        return 0
    fi
    # 在 whitelist 段的最后一个条目后插入
    # 找到 ban: 段中 whitelist: 后的第一个非列表行，在其前插入
    local line_num
    line_num=$(grep -n '^\s*-\s*"' "$CONFIG_FILE" | tail -1 | cut -d: -f1)
    if [ -z "$line_num" ]; then
        # 没有找到列表项，在 whitelist: 行后插入
        line_num=$(grep -n 'whitelist:' "$CONFIG_FILE" | head -1 | cut -d: -f1)
        if [ -z "$line_num" ]; then
            error "未找到 whitelist 配置段"
            return 1
        fi
        sed -i "${line_num}a\\    - \"${entry}\"" "$CONFIG_FILE"
    else
        sed -i "${line_num}a\\    - \"${entry}\"" "$CONFIG_FILE"
    fi
    info "已添加白名单: $entry"
}

_remove_whitelist_entry() {
    local entry="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在"
        return 1
    fi
    if ! grep -qF "\"$entry\"" "$CONFIG_FILE" 2>/dev/null; then
        warn "$entry 不在白名单中"
        return 0
    fi
    # 用 grep -nF 定位行号（固定字符串匹配，避免注入），删除最后一个匹配行
    local line_num
    line_num=$(grep -nF "\"$entry\"" "$CONFIG_FILE" | tail -1 | cut -d: -f1)
    if [ -n "$line_num" ]; then
        sed -i "${line_num}d" "$CONFIG_FILE"
    fi
    info "已移除白名单: $entry"
}

do_manage_whitelist() {
    check_root
    print_banner
    printf '%b\n' "${CYAN}${BOLD}📋 白名单管理${NC}\n"

    while true; do
        # 显示当前白名单
        printf '%b\n' "${BOLD}当前白名单:${NC}"
        local wl_lines=()
        local idx=0
        while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            idx=$((idx + 1))
            wl_lines+=("$entry")
            printf '%b\n' "  ${CYAN}[$idx]${NC} ${entry}"
        done <<< "$(_get_whitelist)"

        if [ $idx -eq 0 ]; then
            printf '%b\n' "  ${YELLOW}(空)${NC}"
        fi

        echo ""
        printf '%b\n' "  ${YELLOW}[a]${NC} 添加 IP/CIDR    ${YELLOW}[r]${NC} 删除条目    ${YELLOW}[s]${NC} 热加载生效    ${YELLOW}[q]${NC} 返回"
        echo ""
        printf '%b' "${GREEN}请选择: ${NC}"
        read -r action
        echo ""

        case "$action" in
            a|A)
                local new_entry
                new_entry=$(ask "输入 IP 或 CIDR (如 10.0.0.0/8 或 2001:db8::1)")
                if _validate_ip "$new_entry"; then
                    _add_whitelist_entry "$new_entry"
                else
                    error "格式不正确: $new_entry"
                fi
                ;;
            r|R)
                if [ $idx -eq 0 ]; then
                    warn "白名单为空"
                    continue
                fi
                local del_idx
                del_idx=$(ask "输入要删除的编号 [1-${idx}]")
                if [[ "$del_idx" =~ ^[0-9]+$ ]] && [ "$del_idx" -ge 1 ] && [ "$del_idx" -le $idx ]; then
                    local del_entry="${wl_lines[$((del_idx - 1))]}"
                    _remove_whitelist_entry "$del_entry"
                else
                    error "无效编号"
                fi
                ;;
            s|S)
                if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
                    do_reload
                else
                    warn "服务未运行，配置将在下次启动时生效"
                fi
                ;;
            q|Q)
                return 0
                ;;
            *)
                error "无效选择"
                ;;
        esac

        echo ""
        printf '%b' "${YELLOW}按 Enter 继续...${NC}"
        read -r
    done
}

do_test_alert() {
    check_root

    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在: $CONFIG_FILE"
        return
    fi

    local hostname
    hostname=$(hostname 2>/dev/null || echo "未知")
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    local test_msg="🧪 PortSentinel 告警测试\n\n主机: ${hostname}\n时间: ${now}\n状态: 连接正常"

    # 逐段解析各通道的 enabled 状态和凭据
    local tg_section dingtalk_section email_section
    tg_section=$(sed -n '/^  telegram:/,/^  [a-z]/p' "$CONFIG_FILE")
    dingtalk_section=$(sed -n '/^  dingtalk:/,/^  [a-z]/p' "$CONFIG_FILE")
    email_section=$(sed -n '/^  email:/,/^  [a-z]/p' "$CONFIG_FILE")

    local any_tested=false

    # Telegram 测试
    if echo "$tg_section" | grep -q 'enabled: true'; then
        local bot_token chat_id
        bot_token=$(echo "$tg_section" | grep 'bot_token:' | awk '{print $2}' | tr -d '"')
        chat_id=$(echo "$tg_section" | grep 'chat_id:' | awk '{print $2}' | tr -d '"')
        if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
            printf '%b\n' "${CYAN}[Telegram]${NC} 发送测试消息..."
            local resp
            resp=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
                -d chat_id="$chat_id" \
                -d parse_mode="HTML" \
                --data-urlencode "text=$(printf '%b\n' "$test_msg")" \
                --connect-timeout 10 --max-time 15 2>&1)
            if echo "$resp" | grep -q '"ok":true'; then
                info "Telegram 测试消息发送成功"
            else
                error "Telegram 发送失败: $resp"
            fi
            any_tested=true
        else
            warn "Telegram 已启用但凭据为空，跳过"
        fi
    fi

    # 钉钉测试
    if echo "$dingtalk_section" | grep -q 'enabled: true'; then
        local webhook secret
        webhook=$(echo "$dingtalk_section" | grep 'webhook:' | awk '{print $2}' | tr -d '"')
        secret=$(echo "$dingtalk_section" | grep 'secret:' | awk '{print $2}' | tr -d '"')
        if [ -n "$webhook" ]; then
            local full_url="$webhook"
            # 若配置了签名密钥，计算 HMAC-SHA256 签名
            if [ -n "$secret" ]; then
                local ts_ms
                ts_ms=$(date +%s%3N)
                local sign_str="${ts_ms}\n${secret}"
                local sign
                sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | python3 -c "import sys,urllib.parse;print(urllib.parse.quote_plus(sys.stdin.read().strip()))" 2>/dev/null || true)
                if [ -z "$sign" ]; then
                    # 兜底：无 python3 时用纯 bash percent-encode
                    sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | sed 's/+/%2B/g;s/\//%2F/g;s/=/%3D/g')
                fi
                full_url="${webhook}&timestamp=${ts_ms}&sign=${sign}"
            fi
            printf '%b\n' "${CYAN}[钉钉]${NC} 发送测试消息..."
            local ding_body
            ding_body=$(cat << DINGEOF
{
    "msgtype": "text",
    "text": {
        "content": "PortSentinel 告警测试\n主机: ${hostname}\n时间: ${now}\n状态: 连接正常"
    }
}
DINGEOF
)
            local ding_resp
            ding_resp=$(curl -s -X POST "$full_url" \
                -H 'Content-Type: application/json' \
                -d "$ding_body" \
                --connect-timeout 10 --max-time 15 2>&1)
            if echo "$ding_resp" | grep -q '"errcode":0'; then
                info "钉钉测试消息发送成功"
            else
                error "钉钉发送失败: $ding_resp"
            fi
            any_tested=true
        else
            warn "钉钉已启用但 Webhook 为空，跳过"
        fi
    fi

    # SMTP 邮件测试
    if echo "$email_section" | grep -q 'enabled: true'; then
        local smtp_host smtp_port username password mail_to
        smtp_host=$(echo "$email_section" | grep 'smtp_host:' | awk '{print $2}' | tr -d '"')
        smtp_port=$(echo "$email_section" | grep 'smtp_port:' | awk '{print $2}' | tr -d '"')
        username=$(echo "$email_section" | grep 'username:' | awk '{print $2}' | tr -d '"')
        password=$(echo "$email_section" | grep 'password:' | awk '{print $2}' | tr -d '"')
        mail_to=$(echo "$email_section" | grep '^\s*to:' | awk '{print $2}' | tr -d '"')
        if [ -n "$smtp_host" ] && [ -n "$username" ] && [ -n "$password" ] && [ -n "$mail_to" ]; then
            printf '%b\n' "${CYAN}[邮件]${NC} 发送测试邮件..."
            local mail_subject="PortSentinel 告警测试 - ${hostname}"
            local mail_body="主机: ${hostname}\n时间: ${now}\n状态: 连接正常"
            # 优先用 msmtp / sendmail，回退到 curl SMTP
            if command -v msmtp &>/dev/null; then
                printf "To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%b" \
                    "$mail_to" "$mail_subject" "$mail_body" | msmtp "$mail_to" 2>&1 && info "邮件测试发送成功 (msmtp)" || error "邮件发送失败"
            elif command -v sendmail &>/dev/null; then
                printf "To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%b" \
                    "$mail_to" "$mail_subject" "$mail_body" | sendmail "$mail_to" 2>&1 && info "邮件测试发送成功 (sendmail)" || error "邮件发送失败"
            else
                local curl_proto="smtp"
                [ "$smtp_port" = "465" ] && curl_proto="smtps"
                printf '%b\n' "To: ${mail_to}\nSubject: ${mail_subject}\nContent-Type: text/plain; charset=UTF-8\n\n${mail_body}" | \
                    curl -s --url "${curl_proto}://${smtp_host}:${smtp_port}" \
                    --ssl-reqd \
                    --mail-from "$username" \
                    --mail-rcpt "$mail_to" \
                    --user "${username}:${password}" \
                    --connect-timeout 10 --max-time 15 \
                    -T - 2>&1 && info "邮件测试发送成功 (curl)" || error "邮件发送失败"
            fi
            any_tested=true
        else
            warn "邮件已启用但凭据不完整，跳过"
        fi
    fi

    if ! $any_tested; then
        warn "未检测到已启用的告警通道，请先在安装向导或配置文件中启用"
    fi
}

# ── 报告子系统 ──────────────────────────────────────────────

_report_query() {
    local since="$1"
    local db="${DATA_DIR}/monitor.db"
    if [ ! -f "$db" ]; then
        warn "数据库不存在: $db"
        return 0
    fi

    local time_filter=""
    local prev_time_filter=""
    if [ -n "$since" ]; then
        # 白名单验证：只允许安全的时间偏移格式
        if [[ "$since" =~ ^-[0-9]+\ days?$ ]] || [[ "$since" =~ ^start\ of\ day$ ]]; then
            time_filter="AND timestamp >= datetime('now', '$since')"
            # 生成上一周期的过滤条件（用于环比）
            local prev_since
            if [[ "$since" =~ ^-([0-9]+)\ days?$ ]]; then
                local days="${BASH_REMATCH[1]}"
                prev_since="-${days} days"
                prev_time_filter="AND timestamp >= datetime('now', '-$(( days * 2 )) days') AND timestamp < datetime('now', '${since}')"
            elif [ "$since" = "start of day" ]; then
                prev_time_filter="AND timestamp >= datetime('now', '-2 days') AND timestamp < datetime('now', 'start of day')"
            fi
        else
            warn "无效的时间偏移: $since"
            return 1
        fi
    fi

    # ── 基础统计 ──
    REPORT_TOTAL=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE 1=1 ${time_filter};" 2>/dev/null || echo "0")
    REPORT_UNIQUE_IPS=$(sqlite3 "$db" "SELECT COUNT(DISTINCT src_ip) FROM attacks WHERE 1=1 ${time_filter};" 2>/dev/null || echo "0")
    REPORT_BLOCKED=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE blocked=1 ${time_filter};" 2>/dev/null || echo "0")

    # ── 按类型分布 ──
    REPORT_BY_TYPE=$(sqlite3 -separator '|' "$db" \
        "SELECT attack_type, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY attack_type ORDER BY cnt DESC LIMIT 8;" 2>/dev/null || true)

    # ── 按端口分布 ──
    REPORT_BY_PORT=$(sqlite3 -separator '|' "$db" \
        "SELECT dst_port, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY dst_port ORDER BY cnt DESC LIMIT 5;" 2>/dev/null || true)

    # ── 最近攻击记录 ──
    REPORT_RECENT=$(sqlite3 -separator '|' "$db" \
        "SELECT datetime(timestamp,'localtime'), src_ip, attack_type, dst_port, CASE WHEN blocked=1 THEN '封禁' ELSE '监控' END FROM attacks WHERE 1=1 ${time_filter} ORDER BY timestamp DESC LIMIT 10;" 2>/dev/null || true)

    # ── 按小时聚合（趋势图数据） ──
    REPORT_HOURLY=$(sqlite3 -separator '|' "$db" \
        "SELECT strftime('%H', timestamp) as hour, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY hour ORDER BY hour;" 2>/dev/null || true)

    # ── Top 攻击源 IP ──
    REPORT_TOP_IPS=$(sqlite3 -separator '|' "$db" \
        "SELECT src_ip, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY src_ip ORDER BY cnt DESC LIMIT 8;" 2>/dev/null || true)

    # ── 上一周期数据（环比） ──
    REPORT_PREV_TOTAL="0"
    REPORT_PREV_UNIQUE="0"
    REPORT_PREV_BLOCKED="0"
    if [ -n "$prev_time_filter" ]; then
        REPORT_PREV_TOTAL=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE 1=1 ${prev_time_filter};" 2>/dev/null || echo "0")
        REPORT_PREV_UNIQUE=$(sqlite3 "$db" "SELECT COUNT(DISTINCT src_ip) FROM attacks WHERE 1=1 ${prev_time_filter};" 2>/dev/null || echo "0")
        REPORT_PREV_BLOCKED=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE blocked=1 ${prev_time_filter};" 2>/dev/null || echo "0")
    fi

    return 0
}

# ASCII 柱状图渲染器
# 参数：$1=数据（格式：label|value，每行一条）  $2=图表标题  $3=最大柱宽（默认 30）
_report_bar_chart() {
    local data="$1"
    local title="$2"
    local max_bar="${3:-30}"
    local chart=""

    if [ -z "$data" ]; then
        return
    fi

    # 找到最大值用于缩放
    local max_val=0
    while IFS='|' read -r label value; do
        [ -z "$label" ] && continue
        [ "$value" -gt "$max_val" ] 2>/dev/null && max_val=$value
    done <<< "$data"

    if [ "$max_val" -eq 0 ]; then
        return
    fi

    chart="\n${title}"
    while IFS='|' read -r label value; do
        [ -z "$label" ] && continue
        local bar_len=$(( value * max_bar / max_val ))
        [ "$bar_len" -lt 1 ] && [ "$value" -gt 0 ] && bar_len=1
        local bar=""
        for (( i=0; i<bar_len; i++ )); do bar+="█"; done
        local pct=$(( value * 100 / max_val ))
        chart+="\n  $(printf '%-6s' "$label") ${bar} ${value} (${pct}%)"
    done <<< "$data"

    echo "$chart"
}

_report_trend_icon() {
    local current="$1" previous="$2"
    if [ "$previous" -eq 0 ] 2>/dev/null; then
        [ "$current" -gt 0 ] && echo "🆕" || echo "➖"
        return
    fi
    if [ "$current" -gt "$previous" ]; then
        local pct=$(( (current - previous) * 100 / previous ))
        if [ "$pct" -gt 50 ]; then echo "🔴 ↑${pct}%"
        elif [ "$pct" -gt 20 ]; then echo "🟡 ↑${pct}%"
        else echo "🟢 ↑${pct}%"
        fi
    elif [ "$current" -lt "$previous" ]; then
        local pct=$(( (previous - current) * 100 / previous ))
        if [ "$pct" -gt 50 ]; then echo "🟢 ↓${pct}%"
        elif [ "$pct" -gt 20 ]; then echo "🟡 ↓${pct}%"
        else echo "🔴 ↓${pct}%"
        fi
    else
        echo "➖ 持平"
    fi
}

_report_format() {
    local period_label="$1"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "未知")
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    REPORT_BODY="📊 PortSentinel 安全报告"
    REPORT_BODY+="\n━━━━━━━━━━━━━━━━━━━━━━━━"
    REPORT_BODY+="\n📅 时段: ${period_label}"
    REPORT_BODY+="\n🖥️ 主机: ${hostname}"
    REPORT_BODY+="\n⏰ 生成: ${now}"
    REPORT_BODY+="\n"

    # ── 核心指标 + 环比 ──
    local trend_total trend_ip trend_blocked
    trend_total=$(_report_trend_icon "$REPORT_TOTAL" "$REPORT_PREV_TOTAL")
    trend_ip=$(_report_trend_icon "$REPORT_UNIQUE_IPS" "$REPORT_PREV_UNIQUE")
    trend_blocked=$(_report_trend_icon "$REPORT_BLOCKED" "$REPORT_PREV_BLOCKED")

    REPORT_BODY+="\n📈 核心指标:"
    REPORT_BODY+="\n  ▎ 总攻击: ${REPORT_TOTAL} 次  ${trend_total}"
    REPORT_BODY+="\n  ▎ 来源IP: ${REPORT_UNIQUE_IPS} 个  ${trend_ip}"
    REPORT_BODY+="\n  ▎ 已封禁: ${REPORT_BLOCKED} 个  ${trend_blocked}"

    # ── 攻击类型分布 ──
    if [ -n "$REPORT_BY_TYPE" ]; then
        REPORT_BODY+="\n\n🏷️ 攻击类型分布:"
        while IFS='|' read -r type cnt; do
            [ -n "$type" ] && REPORT_BODY+="\n  • ${type}: ${cnt} 次"
        done <<< "$REPORT_BY_TYPE"
    fi

    # ── 高危端口 ──
    if [ -n "$REPORT_BY_PORT" ]; then
        REPORT_BODY+="\n\n🚪 高危端口 TOP5:"
        while IFS='|' read -r port cnt; do
            [ -n "$port" ] && REPORT_BODY+="\n  • :${port} → ${cnt} 次"
        done <<< "$REPORT_BY_PORT"
    fi

    # ── 攻击时段分布（ASCII 柱状图） ──
    if [ -n "$REPORT_HOURLY" ]; then
        local hourly_chart
        hourly_chart=$(_report_bar_chart "$REPORT_HOURLY" "🕐 攻击时段分布 (按小时):" 25)
        if [ -n "$hourly_chart" ]; then
            REPORT_BODY+="\n${hourly_chart}"
        fi
    fi

    # ── Top 攻击源 IP ──
    if [ -n "$REPORT_TOP_IPS" ]; then
        REPORT_BODY+="\n\n🎯 攻击源 TOP8:"
        local rank=0
        while IFS='|' read -r ip cnt; do
            [ -z "$ip" ] && continue
            rank=$((rank + 1))
            local bar=""
            local max_cnt
            max_cnt=$(echo "$REPORT_TOP_IPS" | head -1 | cut -d'|' -f2)
            [ "${max_cnt:-0}" -eq 0 ] && max_cnt=1
            local bar_len=$(( cnt * 20 / max_cnt ))
            [ "$bar_len" -lt 1 ] && bar_len=1
            for (( i=0; i<bar_len; i++ )); do bar+="■"; done
            REPORT_BODY+="\n  ${rank}. $(printf '%-40s' "$ip") ${bar} ${cnt} 次"
        done <<< "$REPORT_TOP_IPS"
    fi

    # ── 最近攻击记录 ──
    if [ -n "$REPORT_RECENT" ]; then
        REPORT_BODY+="\n\n📋 最近攻击记录:"
        while IFS='|' read -r ts ip type port status; do
            [ -n "$ts" ] && REPORT_BODY+="\n  ${ts} ${ip} ${type} :${port} [${status}]"
        done <<< "$REPORT_RECENT"
    fi
}

_report_send() {
    local channel="$1"
    local config_file="$CONFIG_FILE"
    if [ ! -f "$config_file" ]; then error "配置文件不存在"; return 0; fi

    local hostname
    hostname=$(hostname 2>/dev/null || echo "未知")
    local tg_section dingtalk_section email_section
    tg_section=$(sed -n '/^  telegram:/,/^  [a-z]/p' "$config_file")
    dingtalk_section=$(sed -n '/^  dingtalk:/,/^  [a-z]/p' "$config_file")
    email_section=$(sed -n '/^  email:/,/^  [a-z]/p' "$config_file")

    local sent=false

    if [ "$channel" = "telegram" ] || [ "$channel" = "all" ]; then
        if echo "$tg_section" | grep -q 'enabled: true'; then
            local bot_token chat_id
            bot_token=$(echo "$tg_section" | grep 'bot_token:' | awk '{print $2}' | tr -d '"')
            chat_id=$(echo "$tg_section" | grep 'chat_id:' | awk '{print $2}' | tr -d '"')
            if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
                printf '%b\n' "${CYAN}[Telegram]${NC} 发送报告..."
                local resp
                resp=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
                    -d chat_id="$chat_id" \
                    -d parse_mode="HTML" \
                    --data-urlencode "text=$(printf '%b\n' "$REPORT_BODY")" \
                    --connect-timeout 10 --max-time 15 2>&1)
                echo "$resp" | grep -q '"ok":true' && info "Telegram 发送成功" || error "Telegram 发送失败: $resp"
                sent=true
            else
                warn "Telegram 凭据为空"
            fi
        elif [ "$channel" = "telegram" ]; then
            warn "Telegram 未启用"
        fi
    fi

    if [ "$channel" = "dingtalk" ] || [ "$channel" = "all" ]; then
        if echo "$dingtalk_section" | grep -q 'enabled: true'; then
            local webhook secret
            webhook=$(echo "$dingtalk_section" | grep 'webhook:' | awk '{print $2}' | tr -d '"')
            secret=$(echo "$dingtalk_section" | grep 'secret:' | awk '{print $2}' | tr -d '"')
            if [ -n "$webhook" ]; then
                printf '%b\n' "${CYAN}[钉钉]${NC} 发送报告..."
                local full_url="$webhook"
                if [ -n "$secret" ]; then
                    local ts_ms sign_str sign
                    ts_ms=$(date +%s%3N)
                    sign_str="${ts_ms}\n${secret}"
                    sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | sed 's/+/%2B/g;s/\//%2F/g;s/=/%3D/g')
                    full_url="${webhook}&timestamp=${ts_ms}&sign=${sign}"
                fi
                # 将报告内容中的换行转义为 JSON 安全的 \n 序列
                local report_json
                report_json=$(printf '%b\n' "$REPORT_BODY" | head -20 | sed ':a;N;$!ba;s/\n/\\n/g')
                local ding_resp
                ding_resp=$(curl -s -X POST "$full_url" \
                    -H 'Content-Type: application/json' \
                    -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"PortSentinel 安全报告\n${report_json}\"}}" \
                    --connect-timeout 10 --max-time 15 2>&1)
                echo "$ding_resp" | grep -q '"errcode":0' && info "钉钉发送成功" || error "钉钉发送失败: $ding_resp"
                sent=true
            else
                warn "钉钉 Webhook 为空"
            fi
        elif [ "$channel" = "dingtalk" ]; then
            warn "钉钉未启用"
        fi
    fi

    if [ "$channel" = "email" ] || [ "$channel" = "all" ]; then
        if echo "$email_section" | grep -q 'enabled: true'; then
            local smtp_host smtp_port username password mail_to
            smtp_host=$(echo "$email_section" | grep 'smtp_host:' | awk '{print $2}' | tr -d '"')
            smtp_port=$(echo "$email_section" | grep 'smtp_port:' | awk '{print $2}' | tr -d '"')
            username=$(echo "$email_section" | grep 'username:' | awk '{print $2}' | tr -d '"')
            password=$(echo "$email_section" | grep 'password:' | awk '{print $2}' | tr -d '"')
            mail_to=$(echo "$email_section" | grep '^\s*to:' | awk '{print $2}' | tr -d '"')
            if [ -n "$smtp_host" ] && [ -n "$username" ] && [ -n "$password" ] && [ -n "$mail_to" ]; then
                printf '%b\n' "${CYAN}[邮件]${NC} 发送报告..."
                local curl_proto="smtp"
                [ "$smtp_port" = "465" ] && curl_proto="smtps"
                local mail_resp
                mail_resp=$(printf "To: %s\nSubject: =?UTF-8?B?%s?=\nContent-Type: text/plain; charset=UTF-8\n\n%s" \
                    "$mail_to" \
                    "$(echo -n "PortSentinel 安全报告 - ${hostname}" | base64)" \
                    "$(printf '%b\n' "$REPORT_BODY")" | \
                    curl -s --url "${curl_proto}://${smtp_host}:${smtp_port}" \
                    --ssl-reqd --mail-from "$username" --mail-rcpt "$mail_to" \
                    --user "${username}:${password}" \
                    --connect-timeout 10 --max-time 15 -T - 2>&1)
                if [ -z "$mail_resp" ] || ! echo "$mail_resp" | grep -qi 'error\|denied\|fail\|535\|550\|553'; then
                    info "邮件发送成功"
                else
                    error "邮件发送失败: $mail_resp"
                fi
                sent=true
            else
                warn "邮件凭据不完整"
            fi
        elif [ "$channel" = "email" ]; then
            warn "邮件未启用"
        fi
    fi

    $sent || warn "无可用发送通道"
}

# 生成报告[查询 + 格式化]，不发送
do_report_view() {
    local period="$1" label="$2"
    printf '%b\n' "${CYAN}正在查询 ${label} 的攻击数据...${NC}"
    if ! _report_query "$period"; then
        return
    fi
    _report_format "$label"
    echo ""
    printf '%b\n' "$REPORT_BODY"
    echo ""
}

# 生成报告并发送到指定通道
do_report_send() {
    local period="$1" label="$2" channel="$3"
    printf '%b\n' "${CYAN}正在生成 ${label} 报告...${NC}"
    if ! _report_query "$period"; then
        return
    fi
    _report_format "$label"
    _report_send "$channel"
}

# 定时报告[通过 cron]
do_report_schedule() {
    check_root

    local report_type
    report_type=$(ask_choice "报告类型" "日报 (每天 09:00)" "周报 (每周一 09:00)" "月报 (每月1日 09:00)" "自定义 cron")
    local cron_expr="" period="" label=""

    case $report_type in
        1) cron_expr="0 9 * * *"; period="-1 day"; label="日报" ;;
        2) cron_expr="0 9 * * 1"; period="-7 days"; label="周报" ;;
        3) cron_expr="0 9 1 * *"; period="-30 days"; label="月报" ;;
        4)
            cron_expr=$(ask "cron 表达式 (分 时 日 月 周)" "0 9 * * *")
            period=$(ask "统计时段 (如: -1 day, -7 days, -30 days)" "-1 day")
            label=$(ask "报告名称" "定时报告")
            ;;
    esac

    local channel
    channel=$(ask_choice "发送通道" "Telegram" "钉钉" "邮件" "全部")
    case $channel in
        1) channel="telegram" ;;
        2) channel="dingtalk" ;;
        3) channel="email" ;;
        4) channel="all" ;;
    esac

    local script_path="/usr/local/bin/port-monitor-report"
    local safe_label="${label//[^a-zA-Z0-9_ -]/}"
    cat > "$script_path" << 'SCRIPTEOF'
#!/bin/bash
# PortSentinel 定时报告
SCRIPTEOF
    # 安全地追加变量替换后的命令行
    printf '"%s" _internal-report "%s" "%s" "%s"\n' \
        "$0" "$period" "$safe_label" "$channel" >> "$script_path"
    chmod +x "$script_path"

    # 注册 cron 任务
    local cron_job="${cron_expr} ${script_path} >> /var/log/port-monitor/report.log 2>&1"
    # 移除旧的同类任务
    crontab -l 2>/dev/null | grep -v "port-monitor-report" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    info "定时报告已配置"
    printf '%b\n' "  ${CYAN}类型:${NC} ${label}"
    printf '%b\n' "  ${CYAN}周期:${NC} ${cron_expr}"
    printf '%b\n' "  ${CYAN}通道:${NC} ${channel}"
    printf '%b\n' "  ${CYAN}日志:${NC} /var/log/port-monitor/report.log"
}

do_report() {
    check_root
    print_banner
    printf '%b\n' "${CYAN}${BOLD}📊 报告中心${NC}\n"

    local period_choice
    period_choice=$(ask_choice "选择时段" "当天" "近 3 天" "近 7 天" "近 30 天" "全部")
    local period="" label=""
    case $period_choice in
        1) period="start of day"; label="当天" ;;
        2) period="-3 days"; label="近 3 天" ;;
        3) period="-7 days"; label="近 7 天" ;;
        4) period="-30 days"; label="近 30 天" ;;
        5) period=""; label="全部" ;;
    esac

    echo ""
    local action
    action=$(ask_choice "操作" "查看报告" "发送报告" "设置定时报告")
    case $action in
        1)
            do_report_view "$period" "$label"
            ;;
        2)
            # 检测已启用的通道
            local channels=() channel_keys=()
            local tg_en ding_en mail_en
            tg_en=$(sed -n '/^  telegram:/,/^  [a-z]/p' "$CONFIG_FILE" | grep -q 'enabled: true' && echo "y" || echo "n")
            ding_en=$(sed -n '/^  dingtalk:/,/^  [a-z]/p' "$CONFIG_FILE" | grep -q 'enabled: true' && echo "y" || echo "n")
            mail_en=$(sed -n '/^  email:/,/^  [a-z]/p' "$CONFIG_FILE" | grep -q 'enabled: true' && echo "y" || echo "n")

            [ "$tg_en" = "y" ] && channels+=("Telegram") && channel_keys+=("telegram")
            [ "$ding_en" = "y" ] && channels+=("钉钉") && channel_keys+=("dingtalk")
            [ "$mail_en" = "y" ] && channels+=("邮件") && channel_keys+=("email")
            [ ${#channels[@]} -gt 1 ] && channels+=("全部") && channel_keys+=("all")

            if [ ${#channels[@]} -eq 0 ]; then
                warn "未检测到已启用的告警通道，请先配置"
                return
            fi

            local ch_choice
            ch_choice=$(ask_choice "发送通道" "${channels[@]}")
            local ch_idx=$((ch_choice - 1))
            do_report_send "$period" "$label" "${channel_keys[$ch_idx]}"
            ;;
        3)
            do_report_schedule
            ;;
    esac
}

do_stats() {
    printf '%b\n' "${CYAN}服务状态:${NC}"
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        printf '%b\n' "  状态: ${GREEN}运行中${NC}"
        local pid
        pid=$(pgrep -x "port-monitor" || true)
        if [ -n "$pid" ]; then
            ps -p "$pid" -o pid,pcpu,pmem,etime --no-headers | awk '{printf "  PID: %s  CPU: %s%%  内存: %s%%  运行: %s\n",$1,$2,$3,$4}'
        fi
        # 尝试从 API 获取详细统计
        if [ -f "$CONFIG_FILE" ]; then
            local api_port api_token
            api_port=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'port:' | awk '{print $2}' | tr -d '"')
            api_token=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'token:' | awk '{print $2}' | tr -d '"')
            if [ -n "$api_port" ] && [ -n "$api_token" ]; then
                local api_resp
                api_resp=$(curl -s "http://127.0.0.1:${api_port}/api/status?token=${api_token}" --connect-timeout 3 --max-time 5 2>/dev/null)
                if echo "$api_resp" | grep -q '"version"'; then
                    local ver uptime_s packets ban_hits
                    ver=$(echo "$api_resp" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
                    uptime_s=$(echo "$api_resp" | grep -o '"uptime_seconds":[0-9]*' | cut -d: -f2)
                    packets=$(echo "$api_resp" | grep -o '"packets":[0-9]*' | cut -d: -f2)
                    ban_hits=$(echo "$api_resp" | grep -o '"ban_hits":[0-9]*' | cut -d: -f2)
                    local uptime_fmt
                    if [ -n "$uptime_s" ]; then
                        local h=$((uptime_s / 3600))
                        local m=$(((uptime_s % 3600) / 60))
                        uptime_fmt="${h}h ${m}m"
                    fi
                    printf '%b\n' "  版本: ${CYAN}${ver:-?}${NC}  运行: ${CYAN}${uptime_fmt:-?}${NC}"
                    printf '%b\n' "  处理包数: ${CYAN}${packets:-0}${NC}  封禁拦截: ${CYAN}${ban_hits:-0}${NC}"
                fi
            fi
        fi
    else
        printf '%b\n' "  状态: ${RED}已停止${NC}"
    fi
}

do_backup() {
    local file="port-monitor-backup-$(date +%Y%m%d%H%M%S).tar.gz"
    if tar -czf "$file" -C / etc/port-monitor var/lib/port-monitor 2>/dev/null; then
        info "备份完成: $file"
    else
        error "备份失败，请检查目录是否存在"
    fi
}

# ── IP 溯源查询 ─────────────────────────────────────────────

do_ip_lookup() {
    local ip="$1"

    if [ -z "$ip" ]; then
        ip=$(ask "输入要查询的 IP")
    fi

    if ! _validate_ip "$ip"; then
        error "IP 格式不正确: $ip"
        return 0
    fi

    local box_w=62
    printf '%b\n' "${CYAN}正在溯源 ${ip} ...${NC}"
    echo ""

    # ── 1. 反向 DNS ──
    local rdns=""
    rdns=$(host "$ip" 2>/dev/null | grep "domain name pointer" | awk '{print $NF}' | sed 's/\.$//' || true)
    if [ -z "$rdns" ]; then
        rdns=$(dig -x "$ip" +short 2>/dev/null | sed 's/\.$//' || true)
    fi
    [ -z "$rdns" ] && rdns="(无记录)"

    # ── 2. GeoIP (ip-api.com) ──
    local resp
    resp=$(curl -s "http://ip-api.com/json/${ip}?lang=zh-CN&fields=status,country,regionName,city,isp,org,as,query" \
        --connect-timeout 10 --max-time 15 2>&1)

    local country="" region="" city="" isp="" org="" asn=""
    if echo "$resp" | grep -q '"status":"success"'; then
        country=$(echo "$resp" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        region=$(echo "$resp" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
        city=$(echo "$resp" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
        isp=$(echo "$resp" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
        org=$(echo "$resp" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        asn=$(echo "$resp" | grep -o '"as":"[^"]*"' | cut -d'"' -f4)
    fi

    # ── 3. WHOIS/RDAP 查询 ──
    local whois_info=""
    if command -v whois &>/dev/null; then
        whois_info=$(whois "$ip" 2>/dev/null | grep -iE '^(netname|descr|abuse|org-name|OrgName|org-name):' | head -5 | sed 's/^\s*//' || true)
    fi
    if [ -z "$whois_info" ]; then
        # 回退到 RDAP HTTP API
        local rdap_resp
        rdap_resp=$(curl -s "https://rdap.org/ip/${ip}" --connect-timeout 10 --max-time 15 2>&1)
        if echo "$rdap_resp" | grep -q '"name"'; then
            whois_info=$(echo "$rdap_resp" | grep -o '"name":"[^"]*"' | head -3 | cut -d'"' -f4 | tr '\n' ', ' || true)
        fi
    fi
    [ -z "$whois_info" ] && whois_info="(无记录)"

    # ── 4. 本地历史攻击记录 ──
    local db="${DATA_DIR}/monitor.db"
    local hist_total=0 hist_recent=0 hist_types="" hist_first="" hist_last=""
    if [ -f "$db" ]; then
        # 转义单引号防 SQL 注入（防御深度，已通过 _validate_ip 验证）
        local safe_ip="${ip//\'/\'\'}"
        hist_total=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE src_ip='$safe_ip';" 2>/dev/null || echo "0")
        hist_recent=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE src_ip='$safe_ip' AND timestamp >= datetime('now','-24 hours');" 2>/dev/null || echo "0")
        hist_types=$(sqlite3 -separator ', ' "$db" "SELECT DISTINCT attack_type FROM attacks WHERE src_ip='$safe_ip' LIMIT 5;" 2>/dev/null || true)
        hist_first=$(sqlite3 "$db" "SELECT datetime(min(timestamp),'localtime') FROM attacks WHERE src_ip='$safe_ip';" 2>/dev/null || echo "无记录")
        hist_last=$(sqlite3 "$db" "SELECT datetime(max(timestamp),'localtime') FROM attacks WHERE src_ip='$safe_ip';" 2>/dev/null || echo "无记录")
    fi

    # ── 5. 威胁等级评估 ──
    local threat_level="低" threat_color="$GREEN"
    if [ "$hist_total" -gt 100 ] 2>/dev/null; then
        threat_level="极高" threat_color="$RED$BOLD"
    elif [ "$hist_total" -gt 20 ] 2>/dev/null; then
        threat_level="高" threat_color="$RED"
    elif [ "$hist_total" -gt 5 ] 2>/dev/null; then
        threat_level="中" threat_color="$YELLOW"
    fi

    # ── 6. 封禁状态 ──
    local fw_backend
    fw_backend=$(get_firewall_backend)
    local is_banned=false
    case "$fw_backend" in
        iptables)
            iptables -L INPUT -n 2>/dev/null | grep -q "$ip" && is_banned=true
            ! $is_banned && ip6tables -L INPUT -n 2>/dev/null | grep -q "$ip" && is_banned=true
            ;;
        firewalld)  firewall-cmd --list-rich-rules 2>/dev/null | grep -q "$ip" && is_banned=true ;;
        nftables)   nft list ruleset 2>/dev/null | grep -q "$ip" && is_banned=true ;;
    esac

    # ── 输出报告 ──
    printf '%b\n' "╔$(printf '%0.s═' $(seq 1 $box_w))╗"
    printf '%b\n' "║  🔍 IP 溯源报告: ${CYAN}$(printf '%-43s' "$ip")${NC}  ║"
    printf '%b\n' "╠$(printf '%0.s═' $(seq 1 $box_w))╣"
    printf '%b\n' "║  反向 DNS:  $(printf '%-49s' "${rdns}")  ║"
    printf '%b\n' "║  国家/地区: $(printf '%-49s' "${country:-未知}")  ║"
    printf '%b\n' "║  省份/州:   $(printf '%-49s' "${region:-未知}")  ║"
    printf '%b\n' "║  城市:      $(printf '%-49s' "${city:-未知}")  ║"
    printf '%b\n' "║  运营商:    $(printf '%-49s' "${isp:-未知}")  ║"
    printf '%b\n' "║  组织:      $(printf '%-49s' "${org:-未知}")  ║"
    printf '%b\n' "║  ASN:       $(printf '%-49s' "${asn:-未知}")  ║"
    printf '%b\n' "╠$(printf '%0.s═' $(seq 1 $box_w))╣"
    printf '%b\n' "║  WHOIS:     $(printf '%-49s' "${whois_info:0:49}")  ║"
    printf '%b\n' "╠$(printf '%0.s═' $(seq 1 $box_w))╣"
    printf '%b\n' "║  ${BOLD}本地攻击记录${NC}$(printf '%0.s ' $(seq 1 $((box_w - 14))))║"
    printf '%b\n' "║  总攻击:    $(printf '%-49s' "${hist_total} 次")  ║"
    printf '%b\n' "║  近24小时:  $(printf '%-49s' "${hist_recent} 次")  ║"
    printf '%b\n' "║  攻击类型:  $(printf '%-49s' "${hist_types:-无}")  ║"
    printf '%b\n' "║  首次记录:  $(printf '%-49s' "${hist_first}")  ║"
    printf '%b\n' "║  最近记录:  $(printf '%-49s' "${hist_last}")  ║"
    printf '%b\n' "╠$(printf '%0.s═' $(seq 1 $box_w))╣"
    local ban_status="否"
    $is_banned && ban_status="是"
    printf '%b\n' "║  当前封禁:  $(printf '%-49s' "${ban_status}")  ║"
    printf '%b\n' "║  威胁等级:  ${threat_color}$(printf '%-49s' "${threat_level}")${NC}  ║"
    printf '%b\n' "╚$(printf '%0.s═' $(seq 1 $box_w))╝"
    echo ""
}

# ── 实时攻击监控 ─────────────────────────────────────────────

do_live_monitor() {
    check_root

    local db="${DATA_DIR}/monitor.db"
    if [ ! -f "$db" ]; then
        error "数据库不存在: $db"
        return
    fi

    local last_ts=""
    trap 'echo ""; info "已退出监控"; exit 0' INT TERM

    while true; do
        local rows
        rows=$(sqlite3 -separator '|' "$db" \
            "SELECT datetime(timestamp,'localtime'), src_ip, attack_type, dst_port, CASE WHEN blocked=1 THEN '封禁' ELSE '监控' END \
             FROM attacks ORDER BY timestamp DESC LIMIT 15;" 2>/dev/null || true)

        local current_ts=""
        [ -n "$rows" ] && current_ts=$(echo "$rows" | head -1 | cut -d'|' -f1)

        if [ "$current_ts" != "$last_ts" ]; then
            last_ts="$current_ts"
            clear
            printf '%b\n' "${CYAN}${BOLD}📡 实时攻击监控${NC}  按 Ctrl+C 退出"
            printf '%b\n' "  ───────────────────────────────────────────────────────────────────────────────────"
            printf '%b\n' "${YELLOW}  时间                来源IP                                   类型            端口    服务     状态${NC}"
            printf '%b\n' "  ───────────────────────────────────────────────────────────────────────────────────"

            if [ -n "$rows" ]; then
                echo "$rows" | while IFS='|' read -r ts ip type port status; do
                    local color="$NC"
                    local status_color="$GREEN"
                    case "$type" in
                        brute_force) color="$RED" ;;
                        port_scan)   color="$YELLOW" ;;
                        ddos)        color="$RED$BOLD" ;;
                        honeypot)    color="$RED$BOLD" ;;
                    esac
                    [ "$status" = "封禁" ] && status_color="$RED"

                    local svc
                    svc=$(_port_service "$port")

                    printf "  %-19s ${CYAN}%-40s${NC} ${color}%-15s${NC} %-6s %-9s ${status_color}%s${NC}\n" \
                        "$ts" "$ip" "$type" ":$port" "$svc" "$status"
                done
            else
                printf '%b\n' "  ${YELLOW}暂无攻击记录，等待中...${NC}"
            fi
        fi
        sleep 2
    done
}

# ── 一键健康检查 ─────────────────────────────────────────────

do_health_check() {
    print_banner
    printf '%b\n' "${CYAN}${BOLD}🩺 系统健康检查${NC}\n"

    local issues=0

    # 1. 服务进程
    printf '%b\n' "  ${CYAN}[1/8]${NC} 服务进程..."
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        local pid
        pid=$(pgrep -x "port-monitor" || true)
        info "运行中 [PID: ${pid:-未知}]"
    else
        warn "服务未运行"
        issues=$((issues + 1))
    fi

    # 2. systemd 服务
    printf '%b\n' "  ${CYAN}[2/8]${NC} systemd 服务..."
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        info "已注册并启用"
    else
        warn "服务未注册或未启用"
        issues=$((issues + 1))
    fi

    # 3. 配置文件
    printf '%b\n' "  ${CYAN}[3/8]${NC} 配置文件..."
    if [ -f "$CONFIG_FILE" ]; then
        local perm
        perm=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || echo "未知")
        if [ "$perm" = "600" ]; then
            info "存在，权限 ${perm} ✓"
        else
            warn "存在，但权限为 ${perm}[建议 600]"
            issues=$((issues + 1))
        fi
    else
        error "配置文件不存在: $CONFIG_FILE"
        issues=$((issues + 1))
    fi

    # 4. SQLite 数据库
    printf '%b\n' "  ${CYAN}[4/8]${NC} SQLite 数据库..."
    local db="${DATA_DIR}/monitor.db"
    if [ -f "$db" ]; then
        local db_size
        db_size=$(du -h "$db" 2>/dev/null | awk '{print $1}')
        if sqlite3 "$db" "SELECT COUNT(*) FROM attacks;" &>/dev/null; then
            local total
            total=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks;" 2>/dev/null || echo "?")
            info "正常，${db_size}，${total} 条记录"
        else
            error "数据库损坏或表结构异常"
            issues=$((issues + 1))
        fi
    else
        warn "数据库文件不存在[首次运行后自动创建]"
    fi

    # 5. 防火墙
    printf '%b\n' "  ${CYAN}[5/8]${NC} 防火墙后端..."
    local backend
    backend=$(get_firewall_backend)
    case "$backend" in
        iptables)   info "iptables 可用" ;;
        firewalld)  info "firewalld 可用" ;;
        nftables)   info "nftables 可用" ;;
        *)          error "未检测到可用的防火墙后端"; issues=$((issues + 1)) ;;
    esac

    # 6. 告警通道
    printf '%b\n' "  ${CYAN}[6/8]${NC} 告警通道..."
    local tg_en ding_en mail_en
    tg_en=$(sed -n '/^  telegram:/,/^  [a-z]/p' "$CONFIG_FILE" 2>/dev/null | grep -q 'enabled: true' && echo "y" || echo "n")
    ding_en=$(sed -n '/^  dingtalk:/,/^  [a-z]/p' "$CONFIG_FILE" 2>/dev/null | grep -q 'enabled: true' && echo "y" || echo "n")
    mail_en=$(sed -n '/^  email:/,/^  [a-z]/p' "$CONFIG_FILE" 2>/dev/null | grep -q 'enabled: true' && echo "y" || echo "n")

    local alert_any=false
    [ "$tg_en" = "y" ] && info "Telegram ✓" && alert_any=true
    [ "$ding_en" = "y" ] && info "钉钉 ✓" && alert_any=true
    [ "$mail_en" = "y" ] && info "邮件 ✓" && alert_any=true
    $alert_any || warn "未配置任何告警通道"

    # 7. 磁盘与日志
    printf '%b\n' "  ${CYAN}[7/8]${NC} 磁盘与日志..."
    local disk_usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ]; then
        error "磁盘使用率 ${disk_usage}%[>90%]"
        issues=$((issues + 1))
    else
        info "磁盘使用率 ${disk_usage:-?}%"
    fi

    if [ -d "$LOG_DIR" ]; then
        local log_size
        log_size=$(du -sh "$LOG_DIR" 2>/dev/null | awk '{print $1}')
        info "日志目录: ${log_size:-0}"
    fi

    # 8. 服务资源占用
    printf '%b\n' "  ${CYAN}[8/8]${NC} 服务资源占用..."
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        local pid
        pid=$(pgrep -x "port-monitor" || true)
        if [ -n "$pid" ]; then
            local cpu mem mem_kb uptime_str
            read -r cpu mem < <(ps -p "$pid" -o %cpu,%mem --no-headers 2>/dev/null || echo "0 0")
            mem_kb=$(ps -p "$pid" -o rss --no-headers 2>/dev/null || echo "0")
            uptime_str=$(ps -p "$pid" -o etime --no-headers 2>/dev/null || echo "?")
            local mem_mb
            mem_mb=$(awk "BEGIN{printf \"%.1f\", ${mem_kb}/1024}")
            info "CPU: ${cpu}% | 内存: ${mem_mb}MB (${mem}%) | 运行: ${uptime_str}"
        fi
    else
        warn "服务未运行，跳过资源检测"
    fi

    # 汇总
    echo ""
    if [ $issues -eq 0 ]; then
        printf '%b\n' "  ${GREEN}${BOLD}═══ 检查完成：全部正常 ═══${NC}"
    else
        printf '%b\n' "  ${YELLOW}${BOLD}═══ 检查完成：发现 ${issues} 个问题 ═══${NC}"
    fi
}

# ── 日志清理 ─────────────────────────────────────────────────

do_cleanup() {
    check_root
    print_banner
    printf '%b\n' "${CYAN}${BOLD}🧹 日志与数据清理${NC}\n"

    local days
    days=$(ask "保留最近多少天的数据" "30")

    if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -lt 1 ]; then
        error "天数必须为正整数"
        return
    fi

    # 预览
    printf '%b\n' "\n${CYAN}预览将清理的内容:${NC}"

    local db="${DATA_DIR}/monitor.db"
    local old_records=0
    if [ -f "$db" ]; then
        old_records=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE timestamp < datetime('now', '-${days} days');" 2>/dev/null || echo "0")
        printf '%b\n' "  数据库: ${YELLOW}${old_records}${NC} 条超过 ${days} 天的攻击记录"
    fi

    local old_logs=""
    if [ -d "$LOG_DIR" ]; then
        old_logs=$(find "$LOG_DIR" -name "*.log" -mtime +"$days" 2>/dev/null || true)
        local log_count
        log_count=$(echo "$old_logs" | grep -c '.' 2>/dev/null); log_count="${log_count:-0}"
        local log_size="0"
        [ -n "$old_logs" ] && log_size=$(echo "$old_logs" | xargs du -ch 2>/dev/null | tail -1 | awk '{print $1}')
        printf '%b\n' "  日志文件: ${YELLOW}${log_count}${NC} 个旧日志 (${log_size:-0})"
    fi

    local old_backups=""
    old_backups=$(find /tmp -name "port-monitor.bak.*" -mtime +7 2>/dev/null || true)
    local bak_count
    bak_count=$(echo "$old_backups" | grep -c '.' 2>/dev/null); bak_count="${bak_count:-0}"
    printf '%b\n' "  临时备份: ${YELLOW}${bak_count}${NC} 个 /tmp 下的旧备份"

    if [ "$old_records" = "0" ] && [ -z "$old_logs" ] && [ "$bak_count" = "0" ]; then
        info "无需清理"
        return
    fi

    echo ""
    if [ "$(ask_yn "确认执行清理？" "n")" != "y" ]; then
        warn "已取消"
        return
    fi

    # 执行清理
    if [ -f "$db" ] && [ "$old_records" != "0" ]; then
        sqlite3 "$db" "DELETE FROM attacks WHERE timestamp < datetime('now', '-${days} days');" 2>/dev/null
        sqlite3 "$db" "VACUUM;" 2>/dev/null
        info "已清理 ${old_records} 条数据库记录"
    fi

    if [ -n "$old_logs" ]; then
        while IFS= read -r f; do rm -f "$f" 2>/dev/null; done <<< "$old_logs"
        info "已清理旧日志文件"
    fi

    if [ -n "$old_backups" ]; then
        while IFS= read -r f; do rm -f "$f" 2>/dev/null; done <<< "$old_backups"
        info "已清理旧临时备份"
    fi

    echo ""
    info "清理完成"
}

# ── Web 仪表盘 ──────────────────────────────────────────────

do_dashboard() {
    local api_port api_token api_enabled
    if [ -f "$CONFIG_FILE" ]; then
        api_enabled=$(grep -A2 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'enabled:' | awk '{print $2}' | tr -d '"')
        api_port=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'port:' | awk '{print $2}' | tr -d '"')
        api_token=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'token:' | awk '{print $2}' | tr -d '"')
    fi
    api_port="${api_port:-8900}"

    if [ "$api_enabled" != "true" ]; then
        warn "API 未启用，请在配置文件中设置 api.enabled: true"
        return
    fi

    if ! systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        error "服务未运行，请先启动"
        return
    fi

    print_banner
    printf '%b\n' "${CYAN}${BOLD}📊 Web 仪表盘${NC}\n"
    printf '%b\n' "  访问地址: ${GREEN}http://localhost:${api_port}/${NC}"
    printf '%b\n' "  API Token: ${YELLOW}${api_token:-无}${NC}"
    echo ""
    printf '%b\n' "  ${YELLOW}提示:${NC} 在浏览器中打开上述地址即可访问可视化仪表盘"
    printf '%b\n' "  仪表盘包含: 实时攻击趋势、最近攻击列表、封禁管理、攻击源TOP10"
}

# ── 数据导出 ─────────────────────────────────────────────────

do_export() {
    check_root
    print_banner
    printf '%b\n' "${CYAN}${BOLD}📤 数据导出${NC}\n"

    local period
    period=$(ask_choice "导出时段" "近 7 天" "近 30 天" "近 90 天" "全部")
    local days=7
    case $period in
        1) days=7 ;;
        2) days=30 ;;
        3) days=90 ;;
        4) days=3650 ;;
    esac

    local format
    format=$(ask_choice "导出格式" "CSV" "JSON")
    local ext="csv"
    [ "$format" = "2" ] && ext="json"

    local outfile="port-sentinel-export-$(date +%Y%m%d%H%M%S).${ext}"
    local db="${DATA_DIR}/monitor.db"

    if [ ! -f "$db" ]; then
        error "数据库不存在"
        return
    fi

    if [ "$format" = "1" ]; then
        sqlite3 -header -csv "$db" \
            "SELECT datetime(timestamp,'localtime') as time, src_ip, attack_type, dst_port, blocked \
             FROM attacks WHERE timestamp >= datetime('now', '-${days} days') \
             ORDER BY timestamp DESC LIMIT 50000;" > "$outfile" 2>/dev/null
    else
        # sqlite3 -json 需要 3.33.0+，低版本回退到 CSV 格式
        if sqlite3 -json ":memory:" "SELECT 1;" >/dev/null 2>&1; then
            sqlite3 -json "$db" \
                "SELECT datetime(timestamp,'localtime') as time, src_ip, attack_type, dst_port, blocked \
                 FROM attacks WHERE timestamp >= datetime('now', '-${days} days') \
                 ORDER BY timestamp DESC LIMIT 50000;" > "$outfile" 2>/dev/null
        else
            warn "sqlite3 版本不支持 JSON 导出，回退为 CSV 格式"
            ext="csv"
            outfile="${outfile%.json}.${ext}"
            sqlite3 -header -csv "$db" \
                "SELECT datetime(timestamp,'localtime') as time, src_ip, attack_type, dst_port, blocked \
                 FROM attacks WHERE timestamp >= datetime('now', '-${days} days') \
                 ORDER BY timestamp DESC LIMIT 50000;" > "$outfile" 2>/dev/null
        fi
    fi

    if [ -f "$outfile" ] && [ -s "$outfile" ]; then
        local size
        size=$(du -h "$outfile" | awk '{print $1}')
        info "导出完成: ${outfile} (${size})"
    else
        error "导出失败或无数据"
    fi
}

# ── Prometheus 指标 ──────────────────────────────────────────

do_prometheus() {
    local api_port api_token api_enabled
    if [ -f "$CONFIG_FILE" ]; then
        api_enabled=$(grep -A2 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'enabled:' | awk '{print $2}' | tr -d '"')
        api_port=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'port:' | awk '{print $2}' | tr -d '"')
        api_token=$(grep -A5 '^api:' "$CONFIG_FILE" 2>/dev/null | grep 'token:' | awk '{print $2}' | tr -d '"')
    fi
    api_port="${api_port:-8900}"

    if [ "$api_enabled" != "true" ]; then
        warn "API 未启用，请在配置文件中设置 api.enabled: true"
        return
    fi

    if ! systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        error "服务未运行，请先启动"
        return
    fi

    print_banner
    printf '%b\n' "${CYAN}${BOLD}📈 Prometheus 指标${NC}\n"
    printf '%b\n' "  指标端点: ${GREEN}http://localhost:${api_port}/api/metrics${NC}"
    echo ""
    printf '%b\n' "  ${YELLOW}可用指标:${NC}"
    printf '%b\n' "    portsentinel_blocked_ips       当前封禁IP数量"
    printf '%b\n' "    portsentinel_attacks_total     攻击总数(按类型)"
    printf '%b\n' "    portsentinel_uptime_seconds    运行时长"
    printf '%b\n' "    portsentinel_packets_total     处理包数"
    printf '%b\n' "    portsentinel_ban_hits_total    封禁拦截次数"
    echo ""
    printf '%b\n' "  ${YELLOW}Grafana 配置:${NC}"
    printf '%b\n' "    在 Prometheus 中添加 scrape_configs:"
    printf '%b\n' "    - job_name: 'portsentinel'"
    printf '%b\n' "      static_configs:"
    printf '%b\n' "        - targets: ['localhost:${api_port}']"
    printf '%b\n' "      metrics_path: '/api/metrics'"
    [ -n "$api_token" ] && printf '%b\n' "      params:"
    [ -n "$api_token" ] && printf '%b\n' "        token: ['${api_token}']"
}

show_menu() {
    clear

    # ── 顶部状态栏 ──
    local hostname_str uptime_str cpu_str mem_str
    hostname_str=$(hostname 2>/dev/null | cut -c1-14 || echo "?")
    uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' | cut -c1-10 || uptime 2>/dev/null | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | cut -c1-10 || echo "?")
    cpu_str=$(awk '/^cpu /{u=$2+$3; t=$2+$3+$4+$5+$6+$7+$8; if(t>0) printf "%.0f%%", (1-$5/t)*100}' /proc/stat 2>/dev/null || echo "?")
    mem_str=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f%%", $3/$2*100}' || echo "?")

    printf '%b\n' "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}${CYAN}║${NC}  ${BOLD}PortSentinel${NC} v${PORTMONITOR_VERSION}  " && printf "${CYAN}│${NC}  主机: ${GREEN}%-16s${NC}" "$hostname_str" && printf "${CYAN}│${NC} 运行: ${GREEN}%-12s${NC} ${CYAN}║${NC}\n" "$uptime_str"
    printf "${BOLD}${CYAN}║${NC}  " && printf "CPU: ${YELLOW}%-5s${NC} " "$cpu_str" && printf "${CYAN}│${NC} 内存: ${YELLOW}%-5s${NC} " "$mem_str"

    # 服务状态
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        printf "${CYAN}│${NC} 状态: ${GREEN}运行中${NC}"
    else
        printf "${CYAN}│${NC} 状态: ${RED}已停止${NC}"
    fi
    printf "     ${CYAN}║${NC}\n"

    printf '%b\n' "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        # ── 服务控制 ──
        printf '%b\n' "  ${BOLD}${GREEN}服务控制${NC}"
        printf '%b\n' "  ${YELLOW}[ 1]${NC} 启动服务       ${YELLOW}[ 2]${NC} 停止服务       ${YELLOW}[ 3]${NC} 重启服务"
        printf '%b\n' "  ${YELLOW}[ 4]${NC} 热加载配置"
        echo ""
        # ── 监控查询 ──
        printf '%b\n' "  ${BOLD}${CYAN}监控查询${NC}"
        printf '%b\n' "  ${YELLOW}[ 5]${NC} 查看状态       ${YELLOW}[ 6]${NC} 查看统计       ${YELLOW}[ 7]${NC} 查看封禁IP"
        printf '%b\n' "  ${YELLOW}[ 8]${NC} 查看日志       ${YELLOW}[ 9]${NC} 实时监控       ${YELLOW}[10]${NC} IP溯源查询"
        echo ""
        # ── 告警报告 ──
        printf '%b\n' "  ${BOLD}${YELLOW}告警报告${NC}"
        printf '%b\n' "  ${YELLOW}[11]${NC} 测试告警       ${YELLOW}[12]${NC} 报告中心       ${YELLOW}[13]${NC} 健康检查"
        echo ""
        # ── 数据导出 ──
        printf '%b\n' "  ${BOLD}${MAGENTA}数据与面板${NC}"
        printf '%b\n' "  ${YELLOW}[14]${NC} Web仪表盘      ${YELLOW}[15]${NC} 导出数据       ${YELLOW}[16]${NC} Prometheus指标"
        echo ""
        # ── 系统维护 ──
        printf '%b\n' "  ${BOLD}${RED}系统维护${NC}"
        printf '%b\n' "  ${YELLOW}[17]${NC} 手动解封       ${YELLOW}[18]${NC} 白名单管理     ${YELLOW}[19]${NC} 编辑配置"
        printf '%b\n' "  ${YELLOW}[20]${NC} 更新程序       ${YELLOW}[21]${NC} 备份配置       ${YELLOW}[22]${NC} 日志清理"
        printf '%b\n' "  ${YELLOW}[ 0]${NC} 退出"
        echo ""
    else
        printf '%b\n' "  ${BOLD}${GREEN}安装${NC}"
        printf '%b\n' "  ${YELLOW}[1]${NC} 安装程序       ${YELLOW}[0]${NC} 退出"
        echo ""
    fi
}

show_menu_loop() {
    while true; do
        show_menu

        if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
            printf '%b' "${GREEN}请选择 [0-22]: ${NC}"
            read -r choice
            echo ""
            case $choice in
                1)  do_start ;;
                2)  do_stop ;;
                3)  do_restart ;;
                4)  do_reload ;;
                5)  do_status ;;
                6)  do_stats ;;
                7)  do_view_bans ;;
                8)  do_logs ;;
                9)  do_live_monitor ;;
                10) do_ip_lookup ;;
                11) do_test_alert ;;
                12) do_report ;;
                13) do_health_check ;;
                14) do_dashboard ;;
                15) do_export ;;
                16) do_prometheus ;;
                17) do_unban ;;
                18) do_manage_whitelist ;;
                19) do_edit_config ;;
                20) do_update ;;
                21) do_backup ;;
                22) do_cleanup ;;
                0)  printf '%b\n' "${GREEN}退出${NC}"; exit 0 ;;
                *)  error "无效选择" ;;
            esac
        else
            printf '%b' "${GREEN}请选择 [0-1]: ${NC}"
            read -r choice
            echo ""
            case $choice in
                1)  do_install ;;
                0)  printf '%b\n' "${GREEN}退出${NC}"; exit 0 ;;
                *)  error "无效选择" ;;
            esac
        fi

        echo ""
        printf '%b' "${YELLOW}按 Enter 继续...${NC}"
        read -r
    done
}

main() {
    case "${1:-}" in
        install)    do_install; exit 0 ;;
        uninstall)  do_uninstall; exit 0 ;;
        update)     do_update; exit 0 ;;
        start)      do_start; exit 0 ;;
        stop)       do_stop; exit 0 ;;
        restart)    do_restart; exit 0 ;;
        reload)     do_reload; exit 0 ;;
        status)     do_status; exit 0 ;;
        logs)       do_logs; exit 0 ;;
        test-alert) do_test_alert; exit 0 ;;
        report)     do_report; exit 0 ;;
        _internal-report) _report_query "$2"; _report_format "$3"; _report_send "$4"; exit 0 ;;
        lookup)     do_ip_lookup "$2"; exit 0 ;;
        whitelist)  do_manage_whitelist; exit 0 ;;
        live)       do_live_monitor; exit 0 ;;
        health)     do_health_check; exit 0 ;;
        health-check) do_health_check; exit 0 ;;
        dashboard)  do_dashboard; exit 0 ;;
        export)     do_export; exit 0 ;;
        metrics)    do_prometheus; exit 0 ;;
        backup)     do_backup; exit 0 ;;
        full-uninstall) do_full_uninstall; exit 0 ;;
        cleanup)    do_cleanup; exit 0 ;;
        --version|-v) echo "PortSentinel v${PORTMONITOR_VERSION}"; exit 0 ;;
        *)          show_menu_loop ;;
    esac
}

main "$@"
