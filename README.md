<div align="center">
<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f0f0f,50:fce300,100:00f0ff&height=220&section=header&text=PortSentinel&fontSize=50&fontColor=fce300&fontAlignY=35&desc=Advanced%20Port%20Security%20Guardian&descSize=15&descColor=00f0ff&descAlignY=55&animation=twinkling" width="100%"/>

<br/>

[![License: MIT](https://img.shields.io/badge/License-MIT-fce300?style=flat-square&logo=open-source-initiative&logoColor=black)](LICENSE)
[![Language: Python3](https://img.shields.io/badge/Engine-Python3-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org/)
[![Language: Bash](https://img.shields.io/badge/TUI-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero%20External-fce300?style=flat-square&logo=dependabot&logoColor=black)](#)
[![Platform](https://img.shields.io/badge/Platform-Linux%20(systemd)-00f0ff?style=flat-square&logo=linux&logoColor=white)](#)

<br/>

**`Because your ports deserve a sentinel, not a spectator.`**

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
│   │  原始抓包    │    │  │ 抓包线程  │  │检测线程 │           │ │
│   └──────────────┘    │  │ 解析SYN  │─▶│滑动窗口 │           │ │
│                       │  └──────────┘  │扫描/暴破│           │ │
│                       │                │DDoS判定 │           │ │
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
│               │nftables │  └──────────┘  └──────────┘        │
│               └─────────┘                                     │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │          Bash TUI 管控中枢 (18 项功能 · 全拟态终端)      │  │
│   └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✨ 核心特性 | Core Features

### ⚡ 极速侦测引擎

Python3 原生实现，**零外部依赖**（无需 pip、无需编译）。基于 `AF_PACKET` 原始套接字的流量捕获层，3 线程架构（抓包 / 检测 / 过期解封），**秒级识别**高频端口扫描与敏感协议暴力破解行为。支持协议：

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
└──────────────────────────────────────────────────────┘
```

服务重启后，从 SQLite 重建内存状态表，**防线零中断**。

### 📡 多维告警流

原生集成三大推送通道，安全态势实时触达：

- 🤖 **Telegram Bot** — 支持自定义 Bot Token + Chat ID
- 📱 **钉钉 Webhook** — 企业群机器人安全告警
- 📧 **SMTP 邮件** — 支持 TLS 加密的邮件推送

告警推送采用**异步队列 + 聚合防抖**机制：后台守护线程独立消费，短时间内的多条告警自动合并为一条推送，避免触发 API 速率限制（HTTP 429）。

### 🔒 安全加固

- **IP 分片过滤** — 引擎自动丢弃 IP 分片报文，防止攻击者通过分片绕过 TCP 头部检测
- **YAML 注入防护** — 配置生成时自动转义密码、Webhook URL 中的特殊字符（`"` `\`）
- **原子替换** — 程序更新采用 `rm + install` 原子操作，避免 `Text file busy` 错误
- **配置文件权限** — `config.yaml` 权限锁定为 `600`，仅 root 可读写

### 🔄 自动日志轮转

安装时自动注册 `logrotate` 配置（`/etc/logrotate.d/port-monitor`）：每天轮转、保留 7 天、`copytruncate` 模式不中断引擎文件句柄。

### 🔍 IP 溯源查询

输入攻击 IP，调用 ip-api.com 查询归属地、ASN、运营商，辅助判断攻击来源：

```bash
sudo port-monitor.sh lookup 203.0.113.42
```

### 📡 实时攻击监控

全屏滚动面板，每 2 秒刷新最新攻击记录，带颜色高亮和攻击类型标签：

```bash
sudo port-monitor.sh live
```

### 🩺 一键健康检查

单命令扫描全部 8 个组件：服务进程、systemd、配置权限、SQLite 完整性、防火墙、告警通道、磁盘空间、资源占用：

```bash
sudo port-monitor.sh health
```

### 📊 报告中心

支持查看 / 发送 / 定时报告（日报、周报、月报），通过 cron 自动推送：

```bash
sudo port-monitor.sh report
```

### 🧹 日志清理

按保留天数清理旧日志和数据库记录，先预览再确认：

```bash
sudo port-monitor.sh cleanup
```

---

## 🖥️ 控制台预览 | Console Preview

启动管理脚本后，你将看到如下全拟态终端控制台：

```
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          🛡️  端口安全监控管理系统  🛡️                         ║
║                                                               ║
║     检测端口扫描 | 防御暴力破解 | 自动封禁攻击IP             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════╗
║                     📋 主控制面板                             ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║   [1]  启动服务        [10] 手动解封                         ║
║   [2]  停止服务        [11] IP 溯源查询                      ║
║   [3]  重启服务        [12] 实时攻击监控                     ║
║   [4]  查看状态        [13] 测试告警                         ║
║   [5]  查看统计        [14] 报告中心                         ║
║   [6]  编辑配置        [15] 备份配置                         ║
║   [7]  查看日志        [16] 健康检查                         ║
║   [8]  查看封禁IP      [17] 日志清理                         ║
║   [9]  更新程序        [0]  退出                             ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

实时监控仪表盘：

```
╔═══════════════════════════════════════════════════════════════╗
║                   🔴 实时威胁监控面板                          ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  最近攻击事件:                                                ║
║  ┌─────────────────────────────────────────────────────────┐  ║
║  │ 2026-06-20 14:23:07  203.0.113.42   SSH暴力破解  已封禁 │  ║
║  │ 2026-06-20 14:22:51  198.51.100.88  端口扫描    已封禁 │  ║
║  │ 2026-06-20 14:21:33  192.0.2.15     Redis未授权 已封禁 │  ║
║  │ 2026-06-20 14:20:19  203.0.113.42   MySQL暴破   监控中 │  ║
║  └─────────────────────────────────────────────────────────┘  ║
║                                                               ║
║  检测灵敏度: [██████████] 高 (每秒采样 1000+ 包)             ║
║  拦截引擎:   iptables  |  存储: SQLite + Memory              ║
║  告警通道:   Telegram ✅  钉钉 ✅  SMTP ✅                    ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
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
# 方式一：Git 克隆
git clone https://github.com/linjunhao024-byte/PortSentinel.git
cd PortSentinel
sudo bash port-monitor.sh install

# 方式二：wget 直接下载（无需安装 git）
wget -O port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor
wget -O port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh
chmod +x port-monitor
sudo bash port-monitor.sh install

# 方式三：一行命令（下载 + 安装一步到位）
wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor && wget -qO port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh && chmod +x port-monitor && sudo bash port-monitor.sh install
```

安装向导将自动引导你完成 7 步配置：

```
╔═══════════════════════════════════════════════════════════════╗
║                   🔧 安装向导 (7 步)                          ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  [Step 1/7] 安装路径                                          ║
║  [✓] 程序: /usr/local/bin  配置: /etc/port-monitor           ║
║                                                               ║
║  [Step 2/7] 服务器环境                                        ║
║      (1) 国内云服务器 (自动豁免 VPC 内网/云盾探针)            ║
║      (2) 独立服务器/VPS                                       ║
║      (3) 自定义                                               ║
║                                                               ║
║  [Step 3/7] 告警通道 (输入即验证，失败可重试)                 ║
║      Telegram Bot? → 输入 Token/ID → 自动发送测试消息         ║
║      钉钉 Webhook? → 输入 URL → 自动验证连通性                ║
║      SMTP 邮件?    → 输入账号密码 → 自动发送测试邮件          ║
║                                                               ║
║  [Step 4/7] 封禁策略                                          ║
║      防火墙: iptables / firewalld / nftables                  ║
║      端口扫描封禁: 30m ~ 24h                                  ║
║      暴力破解封禁: 1h ~ 永久                                  ║
║                                                               ║
║  [Step 5/7] 检测规则                                           ║
║      灵敏度: 严格 / 正常 / 宽松                               ║
║      SSH 端口: 默认 22，支持自定义（如 2222）                  ║
║                                                               ║
║  [Step 6/7] 快捷命令 (默认: pm)                               ║
║                                                               ║
║  [Step 7/7] 确认安装 → 部署完成                               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

### CLI 命令

```bash
sudo port-monitor.sh              # 进入管理面板
sudo port-monitor.sh start        # 启动服务
sudo port-monitor.sh stop         # 停止服务
sudo port-monitor.sh restart      # 重启服务
sudo port-monitor.sh status       # 查看状态
sudo port-monitor.sh update       # 更新程序
sudo port-monitor.sh test-alert   # 测试告警通道
sudo port-monitor.sh report       # 报告中心
sudo port-monitor.sh health       # 健康检查
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
  ports: "1-65535"
  protocol: "tcp"

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
      - port: 22          # 安装时可自定义，如非标准 SSH 端口 2222
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

alert:
  telegram:
    enabled: true
    bot_token: "YOUR_BOT_TOKEN"
    chat_id: "YOUR_CHAT_ID"
  dingtalk:
    enabled: true
    webhook: "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
    secret: ""
  email:
    enabled: true
    smtp_host: "smtp.example.com"
    smtp_port: 465
    username: "alert@example.com"
    password: "YOUR_PASSWORD"
    to: "admin@example.com"
  log:
    enabled: true
    path: "/var/log/port-monitor/port-monitor.log"

storage:
  type: "both"
  memory:
    max_items: 100000
    ttl: 1h
  sqlite:
    path: "/var/lib/port-monitor/monitor.db"

ban:
  method: "iptables"
  whitelist:
    - "127.0.0.1"
    - "::1"
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
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
                                    #   ├── blocked_ips  封禁记录
                                    #   └── attacks      攻击事件

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

### 告警示例（Telegram）

```
🚨 PortSentinel 自动封禁
━━━━━━━━━━━━━━━━━━━━━━━━
来源: 203.0.113.42
类型: brute_force
端口: :22
时长: 24 小时
时间: 2026-06-20 14:23:07
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
| 检测引擎 | Python 3 | AF_PACKET 抓包、IP 分片过滤、滑动窗口检测、指针交换并发优化 |
| 告警推送 | Python 3 | 异步队列 + 聚合防抖、Telegram / 钉钉 / SMTP 三通道 |
| 持久化 | SQLite | WAL 模式、批量写入、内存缓存封禁状态 |
| 防火墙 | iptables / firewalld / nftables | 内核级封禁/解封、过期自动解封、重启恢复 |
| 管控中枢 | Bash 4+ | 18 项功能 TUI 菜单、安装向导、配置生成、报告中心 |
| 日志运维 | logrotate | 自动轮转（每天/7天/compress/copytruncate） |

零外部依赖：检测引擎仅使用 Python3 标准库（`socket`、`sqlite3`、`threading`、`queue`、`urllib`、`smtplib`）。

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
