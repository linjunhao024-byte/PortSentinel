#!/bin/bash

# 端口安全监控 - 一体化管理脚本 v1.0.0

set -e

PORTMONITOR_VERSION="1.0.0"

# ── 启动依赖检测 ─────────────────────────────────────────────

_check_deps() {
    local missing=()

    [ "$(uname -s)" != "Linux" ] && echo -e "\033[0;31m[✗]\033[0m 仅支持 Linux 系统（当前: $(uname -s））" && exit 1

    [ -z "$BASH_VERSION" ] && echo -e "\033[0;31m[✗]\033[0m 需要 bash 环境" && exit 1
    local bash_major="${BASH_VERSINFO[0]}"
    [ "$bash_major" -lt 4 ] && echo -e "\033[0;31m[✗]\033[0m 需要 bash 4.0+（当前: ${BASH_VERSION}）" && exit 1

    for cmd in python3 systemctl sqlite3 curl awk sed grep tr; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ! command -v iptables &>/dev/null && ! command -v firewall-cmd &>/dev/null && ! command -v nft &>/dev/null; then
        missing+=("iptables/firewalld/nftables [any one]")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\033[0;31m[✗]\033[0m 缺少必要依赖:"
        for m in "${missing[@]}"; do
            echo -e "  • $m"
        done
        echo ""
        echo -e "\033[1;33m安装参考:\033[0m"
        echo "  Debian/Ubuntu:  apt install python3 sqlite3 curl iptables"
        echo "  CentOS/RHEL:    yum install python3 sqlite curl iptables"
        echo "  Arch:           pacman -S python sqlite curl iptables"
        exit 1
    fi
}

_check_deps

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "\n${RED}[✗] 安装中断，正在回滚...${NC}"
    local protected_dirs=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")
    for item in "${_ROLLBACK_ITEMS[@]}"; do
        local is_protected=false
        for pd in "${protected_dirs[@]}"; do
            [ "$item" = "$pd" ] && is_protected=true && break
        done
        $is_protected && continue
        rm -rf "$item" 2>/dev/null || true
    done
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    echo -e "${YELLOW}[!] 已清理安装残留${NC}"
    exit 1
}

print_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║          🛡️  端口安全监控管理系统  🛡️                         ║"
    echo "║                                                               ║"
    echo "║     检测端口扫描 | 防御暴力破解 | 自动封禁攻击IP             ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}\n"
}

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

# 必填输入：不允许空值
ask() {
    local prompt="$1" default="$2"
    local input=""
    while true; do
        if [ -n "$default" ]; then
            echo -n -e "${YELLOW}${prompt} [${default}]: ${NC}"
        else
            echo -n -e "${YELLOW}${prompt}: ${NC}"
        fi
        read -r input
        if [ -n "$input" ]; then
            echo "$input"
            return
        elif [ -n "$default" ]; then
            echo "$default"
            return
        fi
        error "此项不能为空，请重新输入"
    done
}

# 可选输入：允许空值
ask_optional() {
    local prompt="$1" default="$2"
    local input=""
    if [ -n "$default" ]; then
        echo -n -e "${YELLOW}${prompt} [${default}]: ${NC}"
    else
        echo -n -e "${YELLOW}${prompt}: ${NC}"
    fi
    read -r input
    echo "${input:-$default}"
}

ask_yn() {
    local prompt="$1" default="${2:-n}"
    local input=""
    while true; do
        echo -n -e "${YELLOW}${prompt} [$([ "$default" = "y" ] && echo "Y/n" || echo "y/N")]: ${NC}"
        read -r input
        input=$(echo "${input:-$default}" | tr '[:upper:]' '[:lower:]')
        [[ "$input" =~ ^[yn]$ ]] && echo "$input" && return
        error "请输入 y 或 n"
    done
}

ask_choice() {
    local prompt="$1"
    shift
    local options=("$@")
    local count=${#options[@]}
    local choice=""
    echo -e "${YELLOW}${prompt}${NC}"
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${NC} ${options[$i]}"
    done
    while true; do
        echo -n -e "${GREEN}请选择 [1-${count}]: ${NC}"
        read -r choice
        choice="${choice:-1}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            echo "$choice"
            return
        fi
        error "请输入 1-${count} 之间的数字"
    done
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "需要root权限，请使用: sudo $0"
        exit 1
    fi
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
            echo "unknown"
        fi
    else
        echo "$backend"
    fi
}

do_install() {
    print_banner
    echo -e "${CYAN}欢迎使用安装向导，将引导你完成配置${NC}\n"

    check_root

    if [ ! -f "./port-monitor" ]; then
        error "未找到 port-monitor 可执行文件"
        echo -e "${YELLOW}请从 GitHub 下载:${NC}"
        echo -e "  wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor"
        exit 1
    fi

    trap _install_rollback ERR INT TERM

    print_step "步骤 1/7: 安装路径"
    use_default=$(ask_yn "使用默认路径？(程序:/usr/local/bin 配置:/etc/port-monitor)" "y")
    if [ "$use_default" = "n" ]; then
        INSTALL_DIR=$(ask "程序目录" "$INSTALL_DIR")
        CONFIG_DIR=$(ask "配置目录" "$CONFIG_DIR")
        DATA_DIR=$(ask "数据目录" "$DATA_DIR")
        LOG_DIR=$(ask "日志目录" "$LOG_DIR")
        CONFIG_FILE="${CONFIG_DIR}/config.yaml"
        SHORTCUT_FILE="${CONFIG_DIR}/.shortcut_name"
    fi
    info "路径已配置"

    print_step "步骤 2/7: 服务器环境"
    echo -e "${CYAN}服务器环境会影响监控策略:${NC}"
    echo ""
    echo -e "  ${YELLOW}国内云服务器${NC} (阿里云/腾讯云/华为云等):"
    echo -e "    - 内网流量: 健康检查、云盾扫描、负载均衡探针等"
    echo -e "    - 建议: 忽略内网IP，只监控外网攻击，避免误报"
    echo ""
    echo -e "  ${YELLOW}独立服务器/VPS${NC}:"
    echo -e "    - 内网流量较少"
    echo -e "    - 可以监控所有流量"
    echo ""

    server_env=$(ask_choice "服务器环境" "国内云服务器(阿里云/腾讯云/华为云等)" "独立服务器/VPS/海外云" "自定义配置")
    case $server_env in
        1) MONITOR_MODE="cloud"; IGNORE_INTERNAL="y" ;;
        2) MONITOR_MODE="standalone"; IGNORE_INTERNAL="n" ;;
        3) MONITOR_MODE="custom"; IGNORE_INTERNAL=$(ask_yn "是否忽略内网IP流量？" "y") ;;
    esac
    info "服务器环境已配置: ${MONITOR_MODE}"

    print_step "步骤 3/7: 告警配置"
    ENABLE_TELEGRAM="n"
    ENABLE_DINGTALK="n"
    ENABLE_EMAIL="n"

    # Telegram
    if [ "$(ask_yn "启用 Telegram 告警？" "n")" = "y" ]; then
        ENABLE_TELEGRAM="y"
        while true; do
            TELEGRAM_BOT_TOKEN=$(ask "Bot Token")
            TELEGRAM_CHAT_ID=$(ask "Chat ID")
            echo -e "${CYAN}正在验证 Telegram 连接...${NC}"
            local tg_resp
            tg_resp=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d chat_id="$TELEGRAM_CHAT_ID" \
                -d text="🧪 PortSentinel 告警测试成功" \
                --connect-timeout 10 --max-time 15 2>&1)
            if echo "$tg_resp" | grep -q '"ok":true'; then
                info "Telegram 验证成功"
                break
            else
                error "Telegram 发送失败: $(echo "$tg_resp" | grep -o '"description":"[^"]*"' || echo "$tg_resp")"
                if [ "$(ask_yn "重新输入凭据？" "y")" != "y" ]; then
                    ENABLE_TELEGRAM="n"
                    warn "已跳过 Telegram"
                    break
                fi
            fi
        done
    fi

    # 钉钉
    if [ "$(ask_yn "启用钉钉告警？" "n")" = "y" ]; then
        ENABLE_DINGTALK="y"
        while true; do
            DINGTALK_WEBHOOK=$(ask "Webhook URL")
            DINGTALK_SECRET=$(ask_optional "签名密钥(可选)" "")
            echo -e "${CYAN}正在验证钉钉连接...${NC}"
            local ding_url="$DINGTALK_WEBHOOK"
            if [ -n "$DINGTALK_SECRET" ]; then
                local ts_ms sign_str sign
                ts_ms=$(date +%s%3N)
                sign_str="${ts_ms}\n${DINGTALK_SECRET}"
                sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64 | sed 's/+/-/g;s/\//_/g;s/=//g')
                ding_url="${DINGTALK_WEBHOOK}&timestamp=${ts_ms}&sign=${sign}"
            fi
            local ding_resp
            ding_resp=$(curl -s -X POST "$ding_url" \
                -H 'Content-Type: application/json' \
                -d '{"msgtype":"text","text":{"content":"🧪 PortSentinel 告警测试成功"}}' \
                --connect-timeout 10 --max-time 15 2>&1)
            if echo "$ding_resp" | grep -q '"errcode":0'; then
                info "钉钉验证成功"
                break
            else
                error "钉钉发送失败: $ding_resp"
                if [ "$(ask_yn "重新输入凭据？" "y")" != "y" ]; then
                    ENABLE_DINGTALK="n"
                    warn "已跳过钉钉"
                    break
                fi
            fi
        done
    fi

    # 邮件
    if [ "$(ask_yn "启用邮件告警？" "n")" = "y" ]; then
        ENABLE_EMAIL="y"
        while true; do
            provider=$(ask_choice "邮件服务商" "QQ邮箱" "163邮箱" "Gmail" "自定义")
            case $provider in
                1) EMAIL_HOST="smtp.qq.com"; EMAIL_PORT="465" ;;
                2) EMAIL_HOST="smtp.163.com"; EMAIL_PORT="465" ;;
                3) EMAIL_HOST="smtp.gmail.com"; EMAIL_PORT="587" ;;
                4) EMAIL_HOST=$(ask "SMTP服务器"); EMAIL_PORT=$(ask "端口" "465") ;;
            esac
            EMAIL_USER=$(ask "发件人邮箱")
            EMAIL_PASS=$(ask "密码/授权码")
            EMAIL_TO=$(ask "收件人邮箱")
            echo -e "${CYAN}正在验证邮件连接...${NC}"
            local curl_proto="smtp"
            [ "$EMAIL_PORT" = "465" ] && curl_proto="smtps"
            local mail_resp
            mail_resp=$(echo -e "Subject: PortSentinel 告警测试\nContent-Type: text/plain; charset=UTF-8\n\n🧪 PortSentinel 告警测试成功" | \
                curl -s --url "${curl_proto}://${EMAIL_HOST}:${EMAIL_PORT}" \
                --ssl-reqd \
                --mail-from "$EMAIL_USER" \
                --mail-rcpt "$EMAIL_TO" \
                --user "${EMAIL_USER}:${EMAIL_PASS}" \
                --connect-timeout 10 --max-time 15 \
                -T - 2>&1)
            if [ -z "$mail_resp" ] || ! echo "$mail_resp" | grep -qi 'error\|denied\|fail\|535\|550\|553'; then
                info "邮件验证成功"
                break
            else
                error "邮件发送失败: $mail_resp"
                if [ "$(ask_yn "重新输入凭据？" "y")" != "y" ]; then
                    ENABLE_EMAIL="n"
                    warn "已跳过邮件"
                    break
                fi
            fi
        done
    fi
    info "告警配置完成"

    print_step "步骤 4/7: 封禁策略"
    method=$(ask_choice "封禁方式" "iptables(推荐)" "firewalld" "nftables" "仅告警不封禁")
    case $method in
        1) BAN_METHOD="iptables" ;;
        2) BAN_METHOD="firewalld" ;;
        3) BAN_METHOD="nftables" ;;
        4) BAN_METHOD="none" ;;
    esac

    ENABLE_AUTO_BAN="y"
    if [ "$BAN_METHOD" != "none" ]; then
        ENABLE_AUTO_BAN=$(ask_yn "启用自动封禁？" "y")
        if [ "$ENABLE_AUTO_BAN" = "y" ]; then
            echo ""
            echo -e "${CYAN}封禁时长配置:${NC}"
            echo -e "  ${YELLOW}端口扫描${NC}: 攻击者短时间内扫描大量端口"
            echo -e "  ${YELLOW}暴力破解${NC}: 攻击者反复尝试登录敏感服务(SSH/MySQL等)"
            echo ""

            ban_duration_choice=$(ask_choice "端口扫描封禁时长" "30分钟" "1小时(推荐)" "6小时" "24小时" "自定义")
            case $ban_duration_choice in
                1) SCAN_BAN_DURATION="30m" ;;
                2) SCAN_BAN_DURATION="1h" ;;
                3) SCAN_BAN_DURATION="6h" ;;
                4) SCAN_BAN_DURATION="24h" ;;
                5) SCAN_BAN_DURATION=$(ask "输入时长(如: 30m, 1h, 24h)" "1h") ;;
            esac

            brute_duration_choice=$(ask_choice "暴力破解封禁时长" "1小时" "6小时" "24小时(推荐)" "7天" "永久封禁" "自定义")
            case $brute_duration_choice in
                1) BRUTE_BAN_DURATION="1h" ;;
                2) BRUTE_BAN_DURATION="6h" ;;
                3) BRUTE_BAN_DURATION="24h" ;;
                4) BRUTE_BAN_DURATION="168h" ;;
                5) BRUTE_BAN_DURATION="permanent" ;;
                6) BRUTE_BAN_DURATION=$(ask "输入时长(如: 1h, 24h, 168h)" "24h") ;;
            esac
        fi
        ADMIN_IP=$(ask_optional "管理IP(白名单，防止误封)" "")
    else
        ENABLE_AUTO_BAN="n"
        SCAN_BAN_DURATION="1h"
        BRUTE_BAN_DURATION="24h"
    fi
    info "封禁策略已配置"

    print_step "步骤 5/7: 检测规则"
    echo -e "${CYAN}检测灵敏度说明:${NC}"
    echo -e "  ${YELLOW}严格${NC}: 10个端口/10秒 = 端口扫描告警, 3次SSH连接/分钟 = 暴力破解告警"
    echo -e "  ${YELLOW}正常${NC}: 20个端口/10秒 = 端口扫描告警, 5次SSH连接/分钟 = 暴力破解告警"
    echo -e "  ${YELLOW}宽松${NC}: 50个端口/10秒 = 端口扫描告警, 10次SSH连接/分钟 = 暴力破解告警"
    echo ""

    sensitivity=$(ask_choice "检测灵敏度" "严格 - 10端口/10秒, 3次SSH/分钟" "正常 - 20端口/10秒, 5次SSH/分钟(推荐)" "宽松 - 50端口/10秒, 10次SSH/分钟" "自定义")
    case $sensitivity in
        1) SCAN_THRESHOLD=10; BRUTE_THRESHOLD=3 ;;
        2) SCAN_THRESHOLD=20; BRUTE_THRESHOLD=5 ;;
        3) SCAN_THRESHOLD=50; BRUTE_THRESHOLD=10 ;;
        4) SCAN_THRESHOLD=$(ask "端口扫描阈值(多少个端口/10秒触发告警)" "20"); BRUTE_THRESHOLD=$(ask "SSH破解阈值(多少次连接/分钟触发告警)" "5") ;;
    esac
    info "检测规则已配置: 端口扫描=${SCAN_THRESHOLD}个/10秒, SSH破解=${BRUTE_THRESHOLD}次/分钟"

    # 自定义 SSH 端口
    echo ""
    SSH_PORT=$(ask "SSH 端口（用于暴力破解检测）" "22")
    if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
        warn "端口号无效，使用默认值 22"
        SSH_PORT="22"
    fi
    info "SSH 端口已设置: :${SSH_PORT}"

    print_step "步骤 6/7: 快捷键设置"
    echo -e "${CYAN}设置快捷命令，方便快速打开管理面板${NC}"
    echo -e "${YELLOW}提示: 设置后可在终端直接输入快捷键打开管理面板${NC}"
    echo ""
    SHORTCUT=$(ask "设置快捷命令名" "pm")
    info "快捷命令已设置为: ${SHORTCUT}"

    print_step "步骤 7/7: 确认安装"
    echo -e "${CYAN}配置摘要:${NC}"
    echo -e "  路径: ${INSTALL_DIR}"
    echo -e "  快捷键: ${GREEN}${SHORTCUT}${NC}"
    echo -e "  服务器: $([ "$MONITOR_MODE" = "cloud" ] && echo -e "${GREEN}国内云服务器${NC}" || echo -e "${GREEN}独立服务器${NC}")"
    echo -e "  Telegram: $([ "$ENABLE_TELEGRAM" = "y" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}未启用${NC}")"
    echo -e "  钉钉: $([ "$ENABLE_DINGTALK" = "y" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}未启用${NC}")"
    echo -e "  邮件: $([ "$ENABLE_EMAIL" = "y" ] && echo -e "${GREEN}已启用${NC}" || echo -e "${RED}未启用${NC}")"
    echo -e "  封禁方式: ${BAN_METHOD}"
    if [ "$ENABLE_AUTO_BAN" = "y" ]; then
        if [ "$BRUTE_BAN_DURATION" = "permanent" ]; then
            echo -e "  封禁时长: 端口扫描=${GREEN}${SCAN_BAN_DURATION}${NC}, 暴力破解=${RED}永久封禁${NC}"
        else
            echo -e "  封禁时长: 端口扫描=${GREEN}${SCAN_BAN_DURATION}${NC}, 暴力破解=${GREEN}${BRUTE_BAN_DURATION}${NC}"
        fi
    else
        echo -e "  自动封禁: ${RED}未启用${NC}"
    fi
    echo -e "  SSH端口: :${SSH_PORT:-22}"
    echo -e "  白名单: ${ADMIN_IP:-无}"
    if [ "$IGNORE_INTERNAL" = "y" ]; then
        echo -e "  内网IP: ${GREEN}已忽略（避免云平台误报）${NC}"
    fi
    echo ""

    if [ "$(ask_yn "确认安装？" "y")" != "y" ]; then
        warn "已取消"
        trap - ERR INT TERM
        exit 0
    fi

    print_step "正在安装..."

    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    _ROLLBACK_ITEMS+=("$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR")

    install -m 755 ./port-monitor "$INSTALL_DIR/port-monitor"
    _ROLLBACK_ITEMS+=("$INSTALL_DIR/port-monitor")

    generate_config

    # 仅 root 可读写，防止凭证明文泄露
    chmod 600 "$CONFIG_FILE"
    _ROLLBACK_ITEMS+=("$CONFIG_FILE")

    # 持久化快捷命令名，供卸载时精确清理
    echo "$SHORTCUT" > "$SHORTCUT_FILE"

    create_service
    _ROLLBACK_ITEMS+=("/etc/systemd/system/${SERVICE_NAME}.service")

    create_logrotate

    cp "$0" "/usr/local/bin/port-monitor-ctl"
    chmod +x "/usr/local/bin/port-monitor-ctl"
    ln -sf "/usr/local/bin/port-monitor-ctl" "/usr/local/bin/${SHORTCUT}"

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    # 安装成功，清除回滚 trap
    trap - ERR INT TERM
    info "安装完成！"

    echo ""
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}  安装成功！${NC}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${CYAN}快捷命令:${NC} ${GREEN}${SHORTCUT}${NC}"
    echo -e "  ${CYAN}使用方法:${NC} 在终端输入 ${GREEN}${SHORTCUT}${NC} 回车即可打开管理面板"
    echo ""

    if [ "$(ask_yn "现在启动服务？" "y")" = "y" ]; then
        systemctl start "$SERVICE_NAME"
        if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
            info "服务已启动"
        else
            error "启动失败，查看日志: journalctl -u $SERVICE_NAME -n 20"
        fi
    fi

    echo ""
    if [ "$(ask_yn "是否现在进入管理面板？" "y")" = "y" ]; then
        show_menu_loop
    fi
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

  log:
    enabled: true
    path: "${LOG_DIR}/port-monitor.log"

storage:
  type: "both"
  memory:
    max_items: 100000
    ttl: 1h
  sqlite:
    path: "${DATA_DIR}/monitor.db"

ban:
  method: "$BAN_METHOD"
  whitelist:
    - "127.0.0.1"
    - "::1"
$([ -n "$ADMIN_IP" ] && echo "    - \"$ADMIN_IP\"")
$([ "$IGNORE_INTERNAL" = "y" ] && cat << 'WHITELIST'
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "169.254.0.0/16"
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
        echo -e "${YELLOW}请将新版 port-monitor 放到当前目录后重试${NC}"
        exit 1
    fi

    if [ ! -f "$INSTALL_DIR/port-monitor" ]; then
        error "PortSentinel 尚未安装，请先执行安装"
        exit 1
    fi

    echo -e "${CYAN}将更新 PortSentinel 程序文件（配置和数据保留不变）${NC}\n"

    local backup="/tmp/port-monitor.bak.$(date +%s)"
    cp "$INSTALL_DIR/port-monitor" "$backup"
    info "已备份旧版本到 $backup"

    # 原子替换：先删后写，避免 Text file busy 错误
    rm -f "$INSTALL_DIR/port-monitor"
    install -m 755 ./port-monitor "$INSTALL_DIR/port-monitor"
    info "程序文件已更新"

    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        systemctl restart "$SERVICE_NAME"
        info "服务已重启"
    else
        warn "服务当前未运行，跳过重启"
    fi

    echo ""
    info "更新完成"
}

do_uninstall() {
    check_root
    echo -e "${RED}警告: 将卸载服务（保留配置和数据）${NC}"
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
    info "卸载完成（配置保留在 $CONFIG_DIR）"
}

do_full_uninstall() {
    check_root
    echo -e "${RED}警告: 将删除所有文件，包括配置和数据！${NC}"
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
    systemctl start "$SERVICE_NAME"
    info "服务已启动"
}

do_stop() {
    check_root
    systemctl stop "$SERVICE_NAME"
    info "服务已停止"
}

do_restart() {
    check_root
    systemctl restart "$SERVICE_NAME"
    info "服务已重启"
}

do_status() {
    systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || warn "服务未安装"
}

do_logs() {
    echo -e "${YELLOW}按 Ctrl+C 退出${NC}"
    journalctl -u "$SERVICE_NAME" -f --no-pager
}

do_edit_config() {
    check_root
    ${EDITOR:-vi} "$CONFIG_FILE"
    if [ "$(ask_yn "重启服务使配置生效？" "y")" = "y" ]; then
        do_restart
    fi
}

do_view_bans() {
    check_root
    local backend
    backend=$(get_firewall_backend)
    echo -e "${CYAN}当前封禁的IP (${backend}):${NC}"

    local ips=""
    case "$backend" in
        iptables)
            ips=$(iptables -L INPUT -n 2>/dev/null | grep DROP | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
            ;;
        firewalld)
            ips=$(firewall-cmd --list-rich-rules 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
            ;;
        nftables)
            ips=$(nft list ruleset 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)
            ;;
        *)
            warn "无法检测防火墙后端，请手动检查"
            return
            ;;
    esac

    if [ -z "$ips" ]; then
        echo -e "${YELLOW}暂无封禁${NC}"
    else
        echo "$ips" | sort -u | while read -r ip; do echo -e "  ${RED}$ip${NC}"; done
    fi
}

do_unban() {
    check_root
    local ip
    ip=$(ask "要解封的IP")
    if echo "$ip" | grep -qE '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
        local backend
        backend=$(get_firewall_backend)
        case "$backend" in
            iptables)
                iptables -D INPUT -s "$ip" -j DROP 2>/dev/null && info "已解封 $ip" || warn "IP不在封禁列表"
                ;;
            firewalld)
                firewall-cmd --remove-rich-rule="rule family='ipv4' source address='$ip' reject" --permanent 2>/dev/null \
                    && firewall-cmd --reload 2>/dev/null \
                    && info "已解封 $ip" \
                    || warn "IP不在封禁列表"
                ;;
            nftables)
                nft delete rule inet filter input ip saddr "$ip" drop 2>/dev/null \
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

do_test_alert() {
    check_root

    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在: $CONFIG_FILE"
        return
    fi

    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
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
            echo -e "${CYAN}[Telegram]${NC} 发送测试消息..."
            local resp
            resp=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
                -d chat_id="$chat_id" \
                -d parse_mode="HTML" \
                -d text="$(echo -e "$test_msg")" \
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
                sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null || true)
                if [ -z "$sign" ]; then
                    # 兜底：无 python3 时用纯 bash url-encode
                    sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | sed 's/+/-/g;s/\//_/g;s/=//g')
                fi
                full_url="${webhook}&timestamp=${ts_ms}&sign=${sign}"
            fi
            echo -e "${CYAN}[钉钉]${NC} 发送测试消息..."
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
            echo -e "${CYAN}[邮件]${NC} 发送测试邮件..."
            local mail_subject="PortSentinel 告警测试 - ${hostname}"
            local mail_body="主机: ${hostname}\n时间: ${now}\n状态: 连接正常"
            # 优先用 msmtp / sendmail，回退到 curl SMTP
            if command -v msmtp &>/dev/null; then
                printf "To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s" \
                    "$mail_to" "$mail_subject" "$mail_body" | msmtp "$mail_to" 2>&1 && info "邮件测试发送成功 (msmtp)" || error "邮件发送失败"
            elif command -v sendmail &>/dev/null; then
                printf "To: %s\nSubject: %s\nContent-Type: text/plain; charset=UTF-8\n\n%s" \
                    "$mail_to" "$mail_subject" "$mail_body" | sendmail "$mail_to" 2>&1 && info "邮件测试发送成功 (sendmail)" || error "邮件发送失败"
            else
                local curl_proto="smtp"
                [ "$smtp_port" = "465" ] && curl_proto="smtps"
                echo -e "Subject: ${mail_subject}\nContent-Type: text/plain; charset=UTF-8\n\n${mail_body}" | \
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
        return 1
    fi

    local time_filter=""
    [ -n "$since" ] && time_filter="AND timestamp >= datetime('now', '$since')"

    REPORT_TOTAL=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE 1=1 ${time_filter};" 2>/dev/null || echo "0")
    REPORT_UNIQUE_IPS=$(sqlite3 "$db" "SELECT COUNT(DISTINCT src_ip) FROM attacks WHERE 1=1 ${time_filter};" 2>/dev/null || echo "0")
    REPORT_BLOCKED=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE blocked=1 ${time_filter};" 2>/dev/null || echo "0")

    REPORT_BY_TYPE=$(sqlite3 -separator '|' "$db" \
        "SELECT attack_type, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY attack_type ORDER BY cnt DESC LIMIT 8;" 2>/dev/null || true)

    REPORT_BY_PORT=$(sqlite3 -separator '|' "$db" \
        "SELECT dst_port, COUNT(*) as cnt FROM attacks WHERE 1=1 ${time_filter} GROUP BY dst_port ORDER BY cnt DESC LIMIT 5;" 2>/dev/null || true)

    REPORT_RECENT=$(sqlite3 -separator '|' "$db" \
        "SELECT datetime(timestamp,'localtime'), src_ip, attack_type, dst_port, CASE WHEN blocked=1 THEN '封禁' ELSE '监控' END FROM attacks WHERE 1=1 ${time_filter} ORDER BY timestamp DESC LIMIT 10;" 2>/dev/null || true)

    return 0
}

_report_format() {
    local period_label="$1"
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    REPORT_BODY="📊 PortSentinel 安全报告"
    REPORT_BODY+="\n━━━━━━━━━━━━━━━━━━━━━━━━"
    REPORT_BODY+="\n📅 时段: ${period_label}"
    REPORT_BODY+="\n🖥️ 主机: ${hostname}"
    REPORT_BODY+="\n⏰ 生成: ${now}"
    REPORT_BODY+="\n"
    REPORT_BODY+="\n▎ 总攻击: ${REPORT_TOTAL} 次"
    REPORT_BODY+="\n▎ 来源IP: ${REPORT_UNIQUE_IPS} 个"
    REPORT_BODY+="\n▎ 已封禁: ${REPORT_BLOCKED} 个"

    if [ -n "$REPORT_BY_TYPE" ]; then
        REPORT_BODY+="\n\n🏷️ 攻击类型分布:"
        while IFS='|' read -r type cnt; do
            [ -n "$type" ] && REPORT_BODY+="\n  • ${type}: ${cnt} 次"
        done <<< "$REPORT_BY_TYPE"
    fi

    if [ -n "$REPORT_BY_PORT" ]; then
        REPORT_BODY+="\n\n🚪 高危端口 TOP5:"
        while IFS='|' read -r port cnt; do
            [ -n "$port" ] && REPORT_BODY+="\n  • :${port} → ${cnt} 次"
        done <<< "$REPORT_BY_PORT"
    fi

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
    [ ! -f "$config_file" ] && error "配置文件不存在" && return 1

    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
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
                echo -e "${CYAN}[Telegram]${NC} 发送报告..."
                local resp
                resp=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
                    -d chat_id="$chat_id" \
                    -d parse_mode="HTML" \
                    --data-urlencode "text=$(echo -e "$REPORT_BODY")" \
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
                echo -e "${CYAN}[钉钉]${NC} 发送报告..."
                local full_url="$webhook"
                if [ -n "$secret" ]; then
                    local ts_ms sign_str sign
                    ts_ms=$(date +%s%3N)
                    sign_str="${ts_ms}\n${secret}"
                    sign=$(echo -ne "$sign_str" | openssl dgst -sha256 -hmac "$secret" -binary | base64 | sed 's/+/-/g;s/\//_/g;s/=//g')
                    full_url="${webhook}&timestamp=${ts_ms}&sign=${sign}"
                fi
                local ding_resp
                ding_resp=$(curl -s -X POST "$full_url" \
                    -H 'Content-Type: application/json' \
                    -d "{\"msgtype\":\"text\",\"text\":{\"content\":\"PortSentinel 安全报告\n$(echo -e "$REPORT_BODY" | head -20)\"}}" \
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
                echo -e "${CYAN}[邮件]${NC} 发送报告..."
                local curl_proto="smtp"
                [ "$smtp_port" = "465" ] && curl_proto="smtps"
                local mail_resp
                mail_resp=$(printf "To: %s\nSubject: =?UTF-8?B?%s?=\nContent-Type: text/plain; charset=UTF-8\n\n%s" \
                    "$mail_to" \
                    "$(echo -n "PortSentinel 安全报告 - ${hostname}" | base64)" \
                    "$(echo -e "$REPORT_BODY")" | \
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

# 生成报告（查询 + 格式化），不发送
do_report_view() {
    local period="$1" label="$2"
    echo -e "${CYAN}正在查询 ${label} 的攻击数据...${NC}"
    if ! _report_query "$period"; then
        return
    fi
    _report_format "$label"
    echo ""
    echo -e "$REPORT_BODY"
    echo ""
}

# 生成报告并发送到指定通道
do_report_send() {
    local period="$1" label="$2" channel="$3"
    echo -e "${CYAN}正在生成 ${label} 报告...${NC}"
    if ! _report_query "$period"; then
        return
    fi
    _report_format "$label"
    _report_send "$channel"
}

# 定时报告（通过 cron）
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
    cat > "$script_path" << SCRIPTEOF
#!/bin/bash
# PortSentinel 定时报告 - ${label}
"${0}" _internal-report "${period}" "${label}" "${channel}"
SCRIPTEOF
    chmod +x "$script_path"

    # 注册 cron 任务
    local cron_job="${cron_expr} ${script_path} >> /var/log/port-monitor/report.log 2>&1"
    # 移除旧的同类任务
    crontab -l 2>/dev/null | grep -v "port-monitor-report" | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

    info "定时报告已配置"
    echo -e "  ${CYAN}类型:${NC} ${label}"
    echo -e "  ${CYAN}周期:${NC} ${cron_expr}"
    echo -e "  ${CYAN}通道:${NC} ${channel}"
    echo -e "  ${CYAN}日志:${NC} /var/log/port-monitor/report.log"
}

do_report() {
    check_root
    print_banner
    echo -e "${CYAN}${BOLD}📊 报告中心${NC}\n"

    local period_choice
    period_choice=$(ask_choice "选择时段" "当天" "近 3 天" "近 7 天" "近 30 天" "全部")
    local period="" label=""
    case $period_choice in
        1) period="-0 days"; label="当天" ;;
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
    echo -e "${CYAN}服务状态:${NC}"
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        echo -e "  状态: ${GREEN}运行中${NC}"
        local pid
        pid=$(pgrep -x "port-monitor" || true)
        if [ -n "$pid" ]; then
            ps -p "$pid" -o pid,pcpu,pmem,etime --no-headers | awk '{printf "  PID: %s  CPU: %s%%  内存: %s%%  运行: %s\n",$1,$2,$3,$4}'
        fi
    else
        echo -e "  状态: ${RED}已停止${NC}"
    fi
}

do_backup() {
    local file="port-monitor-backup-$(date +%Y%m%d%H%M%S).tar.gz"
    tar -czf "$file" -C / etc/port-monitor var/lib/port-monitor 2>/dev/null
    info "备份完成: $file"
}

# ── IP 溯源查询 ─────────────────────────────────────────────

do_ip_lookup() {
    local ip="$1"

    if [ -z "$ip" ]; then
        ip=$(ask "输入要查询的 IP")
    fi

    if ! echo "$ip" | grep -qE '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
        error "IP 格式不正确: $ip"
        return 1
    fi

    echo -e "${CYAN}正在查询 ${ip} ...${NC}"
    local resp
    resp=$(curl -s "http://ip-api.com/json/${ip}?lang=zh-CN&fields=status,country,regionName,city,isp,org,as,query" \
        --connect-timeout 10 --max-time 15 2>&1)

    if echo "$resp" | grep -q '"status":"success"'; then
        local country region city isp org asn
        country=$(echo "$resp" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
        region=$(echo "$resp" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
        city=$(echo "$resp" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
        isp=$(echo "$resp" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
        org=$(echo "$resp" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
        asn=$(echo "$resp" | grep -o '"as":"[^"]*"' | cut -d'"' -f4)

        echo ""
        echo -e "╔══════════════════════════════════════════════════╗"
        echo -e "║  🔍 IP 溯源: ${CYAN}$(printf '%-35s' "$ip")${NC}  ║"
        echo -e "╠══════════════════════════════════════════════════╣"
        echo -e "║  国家/地区: $(printf '%-37s' "${country}")  ║"
        echo -e "║  省份/州:   $(printf '%-37s' "${region}")  ║"
        echo -e "║  城市:      $(printf '%-37s' "${city}")  ║"
        echo -e "║  运营商:    $(printf '%-37s' "${isp}")  ║"
        echo -e "║  组织:      $(printf '%-37s' "${org}")  ║"
        echo -e "║  ASN:       $(printf '%-37s' "${asn}")  ║"
        echo -e "╚══════════════════════════════════════════════════╝"
        echo ""

        # 如果在封禁列表中，额外提示
        if iptables -L INPUT -n 2>/dev/null | grep -q "$ip"; then
            warn "该 IP 当前处于封禁状态"
        fi
    else
        error "查询失败: $resp"
    fi
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
            echo -e "${CYAN}${BOLD}📡 实时攻击监控${NC}  按 Ctrl+C 退出"
            echo -e "  ─────────────────────────────────────────────────────────────────────"
            echo -e "${YELLOW}  时间                来源IP             类型            端口   状态${NC}"
            echo -e "  ─────────────────────────────────────────────────────────────────────"

            if [ -n "$rows" ]; then
                echo "$rows" | while IFS='|' read -r ts ip type port status; do
                    local color="$NC"
                    local status_color="$GREEN"
                    case "$type" in
                        brute_force) color="$RED" ;;
                        port_scan)   color="$YELLOW" ;;
                        ddos)        color="$RED$BOLD" ;;
                    esac
                    [ "$status" = "封禁" ] && status_color="$RED"

                    printf "  %-19s ${CYAN}%-18s${NC} ${color}%-15s${NC} %-6s ${status_color}%s${NC}\n" \
                        "$ts" "$ip" "$type" ":$port" "$status"
                done
            else
                echo -e "  ${YELLOW}暂无攻击记录，等待中...${NC}"
            fi
        fi
        sleep 2
    done
}

# ── 一键健康检查 ─────────────────────────────────────────────

do_health_check() {
    print_banner
    echo -e "${CYAN}${BOLD}🩺 系统健康检查${NC}\n"

    local issues=0

    # 1. 服务进程
    echo -e "  ${CYAN}[1/8]${NC} 服务进程..."
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        local pid
        pid=$(pgrep -x "port-monitor" || true)
        info "运行中 (PID: ${pid:-unknown})"
    else
        warn "服务未运行"
        issues=$((issues + 1))
    fi

    # 2. systemd 服务
    echo -e "  ${CYAN}[2/8]${NC} systemd 服务..."
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        info "已注册并启用"
    else
        warn "服务未注册或未启用"
        issues=$((issues + 1))
    fi

    # 3. 配置文件
    echo -e "  ${CYAN}[3/8]${NC} 配置文件..."
    if [ -f "$CONFIG_FILE" ]; then
        local perm
        perm=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
        if [ "$perm" = "600" ]; then
            info "存在，权限 ${perm} ✓"
        else
            warn "存在，但权限为 ${perm}（建议 600）"
            issues=$((issues + 1))
        fi
    else
        error "配置文件不存在: $CONFIG_FILE"
        issues=$((issues + 1))
    fi

    # 4. SQLite 数据库
    echo -e "  ${CYAN}[4/8]${NC} SQLite 数据库..."
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
        warn "数据库文件不存在（首次运行后自动创建）"
    fi

    # 5. 防火墙
    echo -e "  ${CYAN}[5/8]${NC} 防火墙后端..."
    local backend
    backend=$(get_firewall_backend)
    case "$backend" in
        iptables)   info "iptables 可用" ;;
        firewalld)  info "firewalld 可用" ;;
        nftables)   info "nftables 可用" ;;
        *)          error "未检测到可用的防火墙后端"; issues=$((issues + 1)) ;;
    esac

    # 6. 告警通道
    echo -e "  ${CYAN}[6/8]${NC} 告警通道..."
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
    echo -e "  ${CYAN}[7/8]${NC} 磁盘与日志..."
    local disk_usage
    disk_usage=$(df -h / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
    if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ]; then
        error "磁盘使用率 ${disk_usage}%（>90%）"
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
    echo -e "  ${CYAN}[8/8]${NC} 服务资源占用..."
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
        echo -e "  ${GREEN}${BOLD}═══ 检查完成：全部正常 ═══${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}═══ 检查完成：发现 ${issues} 个问题 ═══${NC}"
    fi
}

# ── 日志清理 ─────────────────────────────────────────────────

do_cleanup() {
    check_root
    print_banner
    echo -e "${CYAN}${BOLD}🧹 日志与数据清理${NC}\n"

    local days
    days=$(ask "保留最近多少天的数据" "30")

    if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" -lt 1 ]; then
        error "天数必须为正整数"
        return
    fi

    # 预览
    echo -e "\n${CYAN}预览将清理的内容:${NC}"

    local db="${DATA_DIR}/monitor.db"
    local old_records=0
    if [ -f "$db" ]; then
        old_records=$(sqlite3 "$db" "SELECT COUNT(*) FROM attacks WHERE timestamp < datetime('now', '-${days} days');" 2>/dev/null || echo "0")
        echo -e "  数据库: ${YELLOW}${old_records}${NC} 条超过 ${days} 天的攻击记录"
    fi

    local old_logs=""
    if [ -d "$LOG_DIR" ]; then
        old_logs=$(find "$LOG_DIR" -name "*.log" -mtime +"$days" 2>/dev/null || true)
        local log_count
        log_count=$(echo "$old_logs" | grep -c '.' 2>/dev/null || echo "0")
        local log_size="0"
        [ -n "$old_logs" ] && log_size=$(echo "$old_logs" | xargs du -ch 2>/dev/null | tail -1 | awk '{print $1}')
        echo -e "  日志文件: ${YELLOW}${log_count}${NC} 个旧日志 (${log_size:-0})"
    fi

    local old_backups=""
    old_backups=$(find /tmp -name "port-monitor.bak.*" -mtime +7 2>/dev/null || true)
    local bak_count
    bak_count=$(echo "$old_backups" | grep -c '.' 2>/dev/null || echo "0")
    echo -e "  临时备份: ${YELLOW}${bak_count}${NC} 个 /tmp 下的旧备份"

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
        echo "$old_logs" | xargs rm -f 2>/dev/null
        info "已清理旧日志文件"
    fi

    if [ -n "$old_backups" ]; then
        echo "$old_backups" | xargs rm -f 2>/dev/null
        info "已清理旧临时备份"
    fi

    echo ""
    info "清理完成"
}

show_menu() {
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        print_banner
        echo -e "${CYAN}${BOLD}管理菜单:${NC}\n"
        echo -e "  ${YELLOW}[1]${NC}  启动服务        ${YELLOW}[10]${NC} 手动解封"
        echo -e "  ${YELLOW}[2]${NC}  停止服务        ${YELLOW}[11]${NC} IP 溯源查询"
        echo -e "  ${YELLOW}[3]${NC}  重启服务        ${YELLOW}[12]${NC} 实时攻击监控"
        echo -e "  ${YELLOW}[4]${NC}  查看状态        ${YELLOW}[13]${NC} 测试告警"
        echo -e "  ${YELLOW}[5]${NC}  查看统计        ${YELLOW}[14]${NC} 报告中心"
        echo -e "  ${YELLOW}[6]${NC}  编辑配置        ${YELLOW}[15]${NC} 备份配置"
        echo -e "  ${YELLOW}[7]${NC}  查看日志        ${YELLOW}[16]${NC} 健康检查"
        echo -e "  ${YELLOW}[8]${NC}  查看封禁IP      ${YELLOW}[17]${NC} 日志清理"
        echo -e "  ${YELLOW}[9]${NC}  更新程序        ${YELLOW}[0]${NC}  退出"
        echo ""
    else
        print_banner
        echo -e "${CYAN}${BOLD}安装菜单:${NC}\n"
        echo -e "  ${YELLOW}[1]${NC}  安装程序"
        echo -e "  ${YELLOW}[0]${NC}  退出"
        echo ""
    fi
}

show_menu_loop() {
    while true; do
        show_menu

        if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
            echo -n -e "${GREEN}请选择 [0-17]: ${NC}"
            read -r choice
            echo ""
            case $choice in
                1)  do_start ;;
                2)  do_stop ;;
                3)  do_restart ;;
                4)  do_status ;;
                5)  do_stats ;;
                6)  do_edit_config ;;
                7)  do_logs ;;
                8)  do_view_bans ;;
                9)  do_update ;;
                10) do_unban ;;
                11) do_ip_lookup ;;
                12) do_live_monitor ;;
                13) do_test_alert ;;
                14) do_report ;;
                15) do_backup ;;
                16) do_health_check ;;
                17) do_cleanup ;;
                0)  echo -e "${GREEN}退出${NC}"; exit 0 ;;
                *)  error "无效选择" ;;
            esac
        else
            echo -n -e "${GREEN}请选择 [0-1]: ${NC}"
            read -r choice
            echo ""
            case $choice in
                1)  do_install ;;
                0)  echo -e "${GREEN}退出${NC}"; exit 0 ;;
                *)  error "无效选择" ;;
            esac
        fi

        echo ""
        echo -n -e "${YELLOW}按 Enter 继续...${NC}"
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
        status)     do_status; exit 0 ;;
        logs)       do_logs; exit 0 ;;
        test-alert) do_test_alert; exit 0 ;;
        report)     do_report; exit 0 ;;
        _internal-report) _report_query "$2"; _report_format "$3"; _report_send "$4"; exit 0 ;;
        lookup)     do_ip_lookup "$2"; exit 0 ;;
        live)       do_live_monitor; exit 0 ;;
        health)     do_health_check; exit 0 ;;
        health-check) do_health_check; exit 0 ;;
        cleanup)    do_cleanup; exit 0 ;;
        --version|-v) echo "PortSentinel v${PORTMONITOR_VERSION}"; exit 0 ;;
        *)          show_menu_loop ;;
    esac
}

main "$@"
