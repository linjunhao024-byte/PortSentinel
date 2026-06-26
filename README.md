<div align="center">
<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f0f0f,50:fce300,100:00f0ff&height=220&section=header&text=LIN-PortSentinel&fontSize=42&fontColor=fce300&fontAlignY=35&desc=Your%20Ports%2C%20Our%20Watch.&descSize=15&descColor=00f0ff&descAlignY=55&animation=twinkling" width="100%"/>

<br/>

**`LIN`** · Port Security Monitor

[![License: MIT](https://img.shields.io/badge/License-MIT-fce300?style=flat-square&logo=open-source-initiative&logoColor=black)](LICENSE)
[![Language: Python3](https://img.shields.io/badge/Engine-Python3-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org/)
[![Language: Bash](https://img.shields.io/badge/TUI-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20External-fce300?style=flat-square&logo=dependabot&logoColor=black)](#)
[![Platform](https://img.shields.io/badge/Platform-Linux%20(systemd)-00f0ff?style=flat-square&logo=linux&logoColor=white)](#)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=flat-square&logo=docker&logoColor=white)](#)

<br/>

**`Your Ports, Our Watch.`**

</div>

<div align="center">

```bash
wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor && wget -qO port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh && chmod +x port-monitor && sed -i 's/\r$//' port-monitor.sh && sudo bash port-monitor.sh install
```

</div>

---

## 📖 项目简介 | Introduction

**PortSentinel** 是一套面向生产环境的高性能端口安全监控与主动防御中枢。它摒弃了传统 IDS/IPS 的臃肿架构，以 **Python 原生侦测引擎**（零外部依赖）为矛、**Bash 全拟态 TUI 管控中枢** 为盾，构建了一套从「实时感知」到「内核级阻断」的完整防御闭环。

> 不是日志分析器，不是流量镜像。是驻守在你网络边界上的 **主动防御实体**。

核心设计哲学：

- **零信任流量** — 默认拒绝一切异常行为，逐级放行
- **全拟态交互** — 终端即控制台，所有操作所见即所得
- **双轨持久化** — 内存热数据 + SQLite 冷存储，重启即恢复防线
- **零外部依赖** — 检测引擎纯 Python3 标准库，无需编译、无需 pip
- **云原生适配** — VPC 内网健康检查、云盾探针自动豁免，拒绝误报

---

## 🏗️ 系统架构 | Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     PortSentinel Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐    ┌──────────────────────────────────────┐ │
│   │  网络流量层   │───▶│         Python 侦测引擎 (3线程)      │ │
│   │  AF_PACKET   │    │  ┌──────────┐  ┌────────┐           │ │
│   │  IPv4 + IPv6 │    │  │ 抓包线程  │  │检测线程 │           │ │
│   └──────────────┘    │  │ 解析SYN  │─▶│滑动窗口 │           │ │
│                       │  └──────────┘  │扫描/暴破│           │ │
│                       │                │DDoS判定 │           │ │
│                       │                │蜜罐检测 │           │ │
│                       │                └────┬────┘           │ │
│                       │  ┌──────────┐       │               │ │
│                       │  │过期解封  │       ▼               │ │
│                       │  │线程      │  封禁+告警            │ │
│                       │  └──────────┘                       │ │
│                       └──────────────────────────────────────┘ │
│                                    │                            │
│                     ┌──────────────┼──────────────┐            │
│                     ▼              ▼              ▼            │
│               ┌─────────┐  ┌──────────┐  ┌──────────┐        │
│               │ 防火墙   │  │ 告警推送  │  │ SQLite   │        │
│               │iptables │  │TG/钉钉   │  │ 持久化   │        │
│               │firewalld│  │SMTP邮件  │  │ 内存缓存 │        │
│               │nftables │  │模板系统  │  │ 自动迁移 │        │
│               └─────────┘  └──────────┘  └──────────┘        │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │     Bash TUI 管控中枢 (19 项功能 · 全拟态终端)           │  │
│   │     HTTP API 接口 · 分布式联动 · 配置热加载              │  │
│   └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✨ 核心特性 | Core Features

### ⚡ 极速侦测引擎

Python3 原生实现，**零外部依赖**（无需 pip、无需编译）。基于 `AF_PACKET` 原始套接字的流量捕获层，3 线程架构（抓包 / 检测 / 过期解封），**秒级识别**高频端口扫描与敏感协议暴力破解行为。

**双栈支持**：同时捕获 IPv4 和 IPv6 流量，自动解析 IPv6 扩展头。

| 协议 | 端口 | 检测模式 |
|------|------|----------|
| SSH | 22 | 暴力破解 / 字典攻击 |
| MySQL | 3306 | 认证失败风暴 |
| Redis | 6379 | 未授权访问 / 异常命令 |
| RDP | 3389 | 暴力破解 / 撞库 |
| FTP | 21 | 匿名登录 / 暴力破解 |
| 自定义 | * | 用户可扩展规则 |

### 🛡️ 内核级阻断

不依赖第三方防火墙管理工具。**直接调用 iptables / firewalld / nftables 系统调用**，执行阶梯式封禁策略：

```
检测阈值触发 ──▶ 临时封禁 30min ──▶ 累犯升级 24h ──▶ 永久拉黑
                   │                  │                  │
                   └── 自动解封       └── 二次确认       └── 人工介入
```

**三种封禁模式**：
- `drop` — 静默丢弃（默认，推荐）
- `reject` — 拒绝并回复 RST
- `rate_limit` — 限速模式（允许低频访问，超出丢弃）

### 🍯 端口蜜罐

开放诱饵端口，任何连接立即封禁（零容忍）：

```yaml
honeypot:
  enabled: true
  ports: [2222, 8888, 33899]
  ban_duration: 7d
```

### 📈 自适应阈值

学习期自动采集流量基线，动态调整检测灵敏度，减少误报：

```yaml
rules:
  adaptive:
    enabled: true
    learning_period: 30m
    multiplier: 3.0
```

### ☁️ 多环境智能自适应

针对云服务器与物理机的不同流量模型，内置智能豁免引擎：

- **VPC 内网健康检查** — 自动识别并豁免云厂商内网探针
- **云盾 / 安骑士探针** — 白名单放行，杜绝安全产品误报
- **CDN 回源流量** — 可配置 CDN 节点 IP 段免检
- **独立物理机** — 全流量审计模式，无豁免

### 💾 双轨持久化

```
┌──────────────────────────────────────────────────────┐
│                   Storage Pipeline                    │
├──────────────────────────────────────────────────────┤
│                                                      │
│  攻击事件 ──▶ 内存环形缓冲区 (热数据, μs 级查询)     │
│       │                                              │
│       └──▶ SQLite 持久化存储 (冷数据, 重启不丢失)    │
│                                                      │
│  拦截状态 ──▶ 内存状态表 (实时同步)                   │
│       │                                              │
│       └──▶ SQLite 持久化表 (防线恢复源)              │
│                                                      │
│  数据库 ──▶ 自动迁移 (版本升级无需手动操作)          │
│                                                      │
└──────────────────────────────────────────────────────┘
```

服务重启后，从 SQLite 重建内存状态表，**防线零中断**。

### 📡 多维告警流

原生集成三大推送通道，安全态势实时触达：

- 🤖 **Telegram Bot** — 支持自定义 Bot Token + Chat ID
- 📱 **钉钉 Webhook** — 企业群机器人安全告警
- 📧 **SMTP 邮件** — 支持 TLS 加密的邮件推送

告警推送采用**异步队列 + 聚合防抖**机制：后台守护线程独立消费，短时间内的多条告警自动合并为一条推送，避免触发 API 速率限制。

**告警模板系统**：支持自定义告警消息格式，内置变量替换：

```yaml
alert:
  templates:
    ban: "🔒 {{hostname}} 封禁 {{src_ip}} | {{attack_type}} | {{duration}}"
```

可用变量：`{{src_ip}}` `{{attack_type}}` `{{dst_port}}` `{{count}}` `{{window}}` `{{level}}` `{{duration}}` `{{time}}` `{{hostname}}` `{{service}}` `{{service_name}}`

### 🌐 IPv6 全链路支持

- **抓包层**：AF_PACKET 天然双栈，AF_INET 回退模式自动创建 IPv6 socket
- **解析层**：完整 IPv6 头部解析，支持扩展头遍历（最多 10 层）
- **防火墙层**：自动选择 `ip6tables` / `family='ipv6'` / `ip6 saddr`
- **白名单**：支持 IPv6 CIDR（`fe80::/10`、`fc00::/7`）
- **地址规范化**：`::ffff:192.168.1.1` 自动转为 `192.168.1.1`

### 🔒 安全加固

- **IP 分片过滤** — 引擎自动丢弃 IP 分片报文，防止攻击者通过分片绕过 TCP 头部检测
- **YAML 注入防护** — 配置生成时自动转义密码、Webhook URL 中的特殊字符
- **原子替换** — 程序更新采用 `rm + install` 原子操作，避免 `Text file busy` 错误
- **配置文件权限** — `config.yaml` 权限锁定为 `600`，仅 root 可读写
- **配置校验** — 启动/热加载时自动验证配置合法性，提前发现错误
- **API 常量时间认证** — 使用 `hmac.compare_digest` 防时序攻击
- **API 请求限制** — POST 请求体限制 1MB，防 OOM 攻击

### 🔄 配置热加载

修改配置后无需重启服务，发送 SIGHUP 即可热加载：

```bash
pm reload                  # CLI 命令
kill -HUP $(pgrep port-monitor)  # 手动发信号
```

热加载范围：检测阈值、白名单、告警配置、蜜罐端口、自适应参数、告警模板。已封禁 IP 和抓包连接不受影响。

### 📊 攻击趋势报告

报告支持 ASCII 柱状图、环比分析、Top 攻击源排名：

```
📈 核心指标:
  ▎ 总攻击: 1523 次  🔴 ↑35%
  ▎ 来源IP: 89 个    🟡 ↑12%
  ▎ 已封禁: 67 个    🟢 ↓8%

🕐 攻击时段分布 (按小时):
  00    ██ 12 (10%)
  14    █████████████████████████ 120 (100%)
```

### 🎯 攻击溯源增强

IP 溯源查询支持反向 DNS、WHOIS/RDAP、本地历史攻击记录、威胁等级评估：

```
╔════════════════════════════════════════════════════════════════╗
║  🔍 IP 溯源报告: 185.220.101.34                               ║
╠════════════════════════════════════════════════════════════════╣
║  反向 DNS:  tor-exit-34.example.net                           ║
║  国家/地区: 德国                                               ║
║  运营商:    Tor Exit Node Operator                             ║
║  ASN:       AS12345 Tor Exit Network                          ║
╠════════════════════════════════════════════════════════════════╣
║  本地攻击记录                                                  ║
║  总攻击:    1523 次                                            ║
║  近24小时:  89 次                                              ║
║  攻击类型:  brute_force, port_scan, honeypot                  ║
╠════════════════════════════════════════════════════════════════╣
║  威胁等级:  极高                                               ║
╚════════════════════════════════════════════════════════════════╝
```

### 🔌 进程关联检测

自动将攻击端口映射到具体服务进程名：

```
2026-06-27 09:58:23 185.220.101.34  brute_force  :22  SSH   封禁
2026-06-27 09:57:15 45.33.32.156    port_scan    :80  HTTP  监控
```

### 🌍 分布式联动

多节点共享封禁列表，一台检测到攻击，所有节点同步封禁：

```yaml
federation:
  enabled: true
  sync_interval: 60s
  peers:
    - url: "http://10.0.0.2:8900"
      token: "shared-secret"
```

### 🔗 HTTP API 接口

轻量 HTTP API，方便外部系统集成：

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/status` | 服务状态 |
| GET | `/api/bans` | 封禁列表 |
| GET | `/api/stats` | 攻击统计 |
| GET | `/api/health` | 健康检查 |
| POST | `/api/ban` | 手动封禁 |
| POST | `/api/unban` | 解封 |

```bash
curl -H "Authorization: Bearer TOKEN" http://localhost:8900/api/status
```

### 📋 白名单管理

TUI 交互式白名单管理，支持 CIDR，修改后热加载生效：

```bash
pm  →  [15] 白名单管理  →  添加/删除/热加载
```

---

## 🖥️ 控制台预览 | Console Preview

启动管理脚本后，你将看到如下全拟态终端控制台：

```
╔══════════════════════════════════════════════════════════════╗
║  PortSentinel v1.0.2  │  主机: web-server-01 │ 运行: 2h 30m  ║
║  CPU: 2%   │ 内存: 1%   │ 状态: 运行中     ║
╚══════════════════════════════════════════════════════════════╝

  服务控制
  [ 1] 启动服务       [ 2] 停止服务       [ 3] 重启服务
  [ 4] 热加载配置

  监控查询
  [ 5] 查看状态       [ 6] 查看统计       [ 7] 查看封禁IP
  [ 8] 查看日志       [ 9] 实时监控       [10] IP溯源查询

  告警报告
  [11] 测试告警       [12] 报告中心       [13] 健康检查

  系统维护
  [14] 手动解封       [15] 白名单管理     [16] 编辑配置
  [17] 更新程序       [18] 备份配置       [19] 日志清理
  [ 0] 退出
```

实时监控仪表盘（含进程关联）：

```
📡 实时攻击监控  按 Ctrl+C 退出
──────────────────────────────────────────────────────────────────────────
  时间                来源IP                                   类型            端口    服务     状态
──────────────────────────────────────────────────────────────────────────
  2026-06-27 09:58:23 185.220.101.34                           brute_force     :22     SSH      封禁
  2026-06-27 09:57:15 45.33.32.156                             port_scan       :80     HTTP     监控
  2026-06-27 09:56:01 192.168.1.100                            honeypot        :2222            封禁
```

---

## 🚀 快速部署 | Quick Start

### 系统依赖

```bash
# Debian / Ubuntu
apt install python3 sqlite3 curl iptables

# CentOS / RHEL / AlmaLinux
yum install python3 sqlite curl iptables

# Arch Linux
pacman -S python sqlite curl iptables
```

### 一键安装

```bash
# 方式一：Git 克隆（自动处理换行符）
git clone https://github.com/linjunhao024-byte/PortSentinel.git
cd PortSentinel
sudo bash port-monitor.sh install

# 方式二：wget 直接下载（无需安装 git）
wget -O port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor
wget -O port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh
chmod +x port-monitor
sed -i 's/\r$//' port-monitor.sh
sudo bash port-monitor.sh install

# 方式三：一行命令（下载 + 安装一步到位）
wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor && wget -qO port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh && chmod +x port-monitor && sed -i 's/\r$//' port-monitor.sh && sudo bash port-monitor.sh install
```

### Docker 部署

```bash
# 构建镜像
docker build -t portsentinel .

# 运行（需要 host 网络和特权）
docker run -d \
  --name port-sentinel \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v $(pwd)/config:/etc/port-monitor:ro \
  -v portsentinel-data:/var/lib/port-monitor \
  -v portsentinel-logs:/var/log/port-monitor \
  portsentinel

# 或使用 docker-compose
docker-compose up -d
```

### CLI 命令

```bash
sudo port-monitor.sh              # 进入管理面板
sudo port-monitor.sh start        # 启动服务
sudo port-monitor.sh stop         # 停止服务
sudo port-monitor.sh restart      # 重启服务
sudo port-monitor.sh reload       # 热加载配置
sudo port-monitor.sh status       # 查看状态
sudo port-monitor.sh update       # 更新程序
sudo port-monitor.sh test-alert   # 测试告警通道
sudo port-monitor.sh report       # 报告中心
sudo port-monitor.sh health       # 健康检查
sudo port-monitor.sh lookup 1.2.3.4  # IP 溯源
sudo port-monitor.sh live         # 实时监控
sudo port-monitor.sh whitelist    # 白名单管理
sudo port-monitor.sh cleanup      # 日志清理
sudo port-monitor.sh uninstall    # 卸载
sudo port-monitor.sh --version    # 查看版本
```

---

## ⚙️ 配置参数 | Configuration

配置文件路径：`/etc/port-monitor/config.yaml`（安装向导自动生成，也可手动编辑）

```yaml
monitor:
  interval: 5s

rules:
  port_scan:
    window: 10s
    thresholds:
      low: 10
      medium: 20
      high: 100
      critical: 1000
    auto_ban: true
    ban_duration: 1h

  brute_force:
    window: 60s
    auto_ban: true
    ban_duration: 24h
    permanent: false
    sensitive_ports:
      - port: 22
        name: "SSH"
        threshold: 5
      - port: 3306
        name: "MySQL"
        threshold: 10
      - port: 6379
        name: "Redis"
        threshold: 3

  ddos:
    window: 5s
    threshold: 1000
    auto_ban: true

  adaptive:
    enabled: false
    learning_period: 30m
    multiplier: 3.0
    recalibrate_interval: 1h

honeypot:
  enabled: false
  ports: [2222, 8888, 33899]
  ban_duration: 7d
  permanent: false

api:
  enabled: false
  host: "127.0.0.1"
  port: 8900
  token: ""

federation:
  enabled: false
  sync_interval: 60s
  peers: []

alert:
  telegram:
    enabled: false
    bot_token: ""
    chat_id: ""
  dingtalk:
    enabled: false
    webhook: ""
    secret: ""
  email:
    enabled: false
    smtp_host: ""
    smtp_port: 465
    username: ""
    password: ""
    to: ""
  log:
    enabled: true
    path: "/var/log/port-monitor/port-monitor.log"
  templates:
    # 自定义告警模板（可选，注释则使用内置默认）
    # ban: "🔒 {{hostname}} 封禁 {{src_ip}} | {{attack_type}} | {{duration}}"

storage:
  sqlite:
    path: "/var/lib/port-monitor/monitor.db"

ban:
  method: "iptables"
  mode: "drop"          # drop | reject | rate_limit
  whitelist:
    - "127.0.0.1"
    - "::1"
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
    - "fe80::/10"
    - "fc00::/7"
```

---

## 📂 目录结构 | Directory Layout

```
/etc/port-monitor/
├── config.yaml                     # 主配置文件（权限 600）
└── .shortcut_name                  # 快捷命令名记录

/etc/logrotate.d/
└── port-monitor                    # 日志轮转配置（每天/保留7天/compress）

/usr/local/bin/
├── port-monitor                    # 检测引擎 (Python3, chmod +x)
├── port-monitor-ctl                # 管理脚本副本
├── port-monitor-report             # 定时报告脚本（cron 调用）
└── pm -> port-monitor-ctl          # 快捷命令 (用户自定义)

/var/lib/port-monitor/
└── monitor.db                      # SQLite 持久化数据库
                                    #   ├── blocked_ips     封禁记录
                                    #   ├── attacks         攻击事件
                                    #   └── schema_version  数据库版本

/var/log/port-monitor/
└── port-monitor.log                # 引擎运行日志（自动轮转）
```

---

## 🌐 云环境适配 | Cloud Adaptation

PortSentinel 内置智能环境检测，针对主流云平台自动调整策略：

| 云平台 | VPC 健康检查豁免 | 云盾探针豁免 | CDN 回源豁免 |
|--------|:---:|:---:|:---:|
| 阿里云 | ✅ | ✅ | 可配置 |
| 腾讯云 | ✅ | ✅ | 可配置 |
| 华为云 | ✅ | ✅ | 可配置 |
| AWS | ✅ | — | 可配置 |
| 独立物理机 | — | — | — |

> 在独立物理机模式下，所有流量均纳入审计范围，无任何自动豁免。

---

## 📡 告警集成 | Alert Integration

### Telegram Bot

安装向导中选择「启用 Telegram」后，输入 Token 和 Chat ID 即可自动验证。也可手动编辑 `config.yaml`：

```yaml
alert:
  telegram:
    enabled: true
    bot_token: "YOUR_BOT_TOKEN"
    chat_id: "YOUR_CHAT_ID"
```

### 钉钉 Webhook

```yaml
alert:
  dingtalk:
    enabled: true
    webhook: "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
    secret: "SEC_YOUR_SECRET"   # 可选，签名密钥
```

### SMTP 邮件

支持 QQ 邮箱 / 163 邮箱 / Gmail / 自定义 SMTP，安装向导中自动配置端口和加密方式：

```yaml
alert:
  email:
    enabled: true
    smtp_host: "smtp.qq.com"
    smtp_port: 465
    username: "alert@example.com"
    password: "YOUR_SMTP_PASSWORD"
    to: "admin@example.com"
```

### 告警示例

**封禁告警：**
```
🚨 PortSentinel 自动封禁
━━━━━━━━━━━━━━━━━━━━━━━━
来源: 203.0.113.42
类型: brute_force
端口: :22
服务: sshd
时长: 24 小时
时间: 2026-06-27 14:23:07
```

**蜜罐告警：**
```
🍯 蜜罐触发 - 零容忍封禁
━━━━━━━━━━━━━━━━━━━━━━━━
来源: 185.220.101.34
触碰端口: :2222
封禁时长: 7 天
```

**聚合摘要：**
```
📊 攻击聚合摘要
━━━━━━━━━━━━━━━━━━━━━━━━
来源: 185.220.101.34
类型: brute_force
端口: :22
300秒内累计 152 次攻击
```

### 测试告警

安装完成后可随时验证告警通道是否正常：

```bash
sudo port-monitor.sh test-alert
```

---

## 🛠️ 技术栈 | Tech Stack

| 组件 | 语言 | 说明 |
|------|------|------|
| 检测引擎 | Python 3 | AF_PACKET 抓包、IPv4/IPv6 双栈、IP 分片过滤、滑动窗口检测、指针交换并发优化 |
| 告警推送 | Python 3 | 异步队列 + 聚合防抖、模板系统、Telegram / 钉钉 / SMTP 三通道 |
| 持久化 | SQLite | WAL 模式、批量写入、内存缓存封禁状态、自动迁移 |
| 防火墙 | iptables / firewalld / nftables | 内核级封禁/解封、三种封禁模式、过期自动解封、重启恢复 |
| HTTP API | Python 3 http.server | 零依赖 RESTful API、常量时间 Token 认证 |
| 分布式联动 | Python 3 urllib | 多节点封禁列表同步、HTTPS 支持 |
| 进程关联 | /proc + ss | 端口到进程名映射、实时刷新 |
| 管控中枢 | Bash 4+ | 19 项功能 TUI 菜单、安装向导、配置生成、报告中心 |
| 日志运维 | logrotate | 自动轮转（每天/7天/compress/copytruncate） |
| 容器化 | Docker | Dockerfile + docker-compose、host 网络模式 |

零外部依赖：检测引擎仅使用 Python3 标准库（`socket`、`sqlite3`、`threading`、`queue`、`urllib`、`smtplib`、`http.server`、`ipaddress`、`hmac`）。

---

## 📋 版本历史 | Changelog

### v1.0.2 (2026-06-27)

**新功能：**
- IPv6 全链路支持（抓包、解析、防火墙、白名单）
- 端口蜜罐模式（诱饵端口零容忍封禁）
- 自适应阈值（学习期自动校准检测灵敏度）
- 配置热加载（SIGHUP 信号触发，无需重启）
- 告警模板系统（`{{variable}}` 变量替换）
- TUI 白名单管理（交互式增删，CIDR 支持）
- 攻击趋势报告（ASCII 柱状图、环比分析、Top 攻击源）
- 攻击溯源增强（反向 DNS、WHOIS/RDAP、历史记录、威胁等级）
- 进程关联检测（端口到服务名映射）
- HTTP API 接口（RESTful、Token 认证）
- 分布式联动（多节点封禁列表同步）
- 告警去重聚合（冷却期内累计计数，汇总发送）
- 配置文件校验（启动/热加载时验证合法性）
- 容器化部署（Dockerfile + docker-compose）
- 速率限制模式（iptables hashlimit 限速封禁）
- 封禁命中率统计（被封 IP 重复攻击计数）
- 数据库自动迁移（schema 版本管理）

**修复：**
- SQLite 线程安全（所有数据库操作加锁保护）
- YAML 解析器冒号误判（URL 等含冒号值不再被当作 dict）
- `hmac.new` → `hmac.HMAC`（使用标准 API）
- iptables 重复规则检查（封禁前先检查规则是否存在）
- nftables handle 提取（`re.search` 显式匹配）
- Bash `echo -e` → `printf '%b\n'`（POSIX 兼容）
- IP 正则拒绝前导零（`099` 不再被接受）
- SQL 注入防护（输入验证 + 单引号转义）
- 邮件验证改用 curl 退出码判断
- Telegram 测试改用 `--data-urlencode`
- 钉钉报告 JSON 换行转义
- API Token 时序攻击防护（`hmac.compare_digest`）
- API Content-Length OOM 防护（1MB 上限）
- SMTP 连接泄漏修复（`try/finally`）

---

## 🤝 参与贡献 | Contributing

欢迎提交 Issue 和 Pull Request。请遵循以下规范：

1. Fork 本仓库并创建特性分支 (`git checkout -b feature/your-feature`)
2. 提交前确保 Shell 脚本通过 ShellCheck，Python 代码通过 `python3 -m py_compile`
3. 提交信息遵循 [Conventional Commits](https://www.conventionalcommits.org/) 规范
4. 发起 Pull Request 并描述你的变更

---

## 📜 开源许可 | License

本项目基于 [MIT License](LICENSE) 开源。

---

<div align="center">

**`PortSentinel`** — *Your ports, our watch.*

<br/>

![Footer](https://capsule-render.vercel.app/api?type=waving&color=0:0f0f0f,50:fce300,100:00f0ff&height=120&section=footer&fontSize=12&fontColor=ffffff&descAlignY=60&animation=twinkling)

</div>
