<div align="center">
<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0f0f0f,50:fce300,100:00f0ff&height=220&section=header&text=PortSentinel&fontSize=50&fontColor=fce300&fontAlignY=35&desc=Advanced%20Port%20Security%20Guardian&descSize=15&descColor=00f0ff&descAlignY=55&animation=twinkling" width="100%"/>

<br/>

[![License: MIT](https://img.shields.io/badge/License-MIT-fce300?style=flat-square&logo=open-source-initiative&logoColor=black)](LICENSE)
[![Language: Go](https://img.shields.io/badge/Engine-Go-00ADD8?style=flat-square&logo=go&logoColor=white)](https://go.dev/)
[![Language: Bash](https://img.shields.io/badge/TUI-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Zero Dependencies](https://img.shields.io/badge/Dependencies-Zero-fce300?style=flat-square&logo=dependabot&logoColor=black)](#)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Cloud-00f0ff?style=flat-square&logo=linux&logoColor=white)](#)

<br/>

**`Because your ports deserve a sentinel, not a spectator.`**

</div>

---

## 📖 项目简介 | Introduction

**PortSentinel** 是一套面向生产环境的高性能端口安全监控与主动防御中枢。它摒弃了传统 IDS/IPS 的臃肿架构，以 **Go 编译型侦测引擎** 为矛、**Bash 全拟态 TUI 管控中枢** 为盾，构建了一套从「毫秒级感知」到「内核级阻断」的完整防御闭环。

> 不是日志分析器，不是流量镜像。是驻守在你网络边界上的 **主动防御实体**。

核心设计哲学：

- **零信任流量** — 默认拒绝一切异常行为，逐级放行
- **全拟态交互** — 终端即控制台，所有操作所见即所得
- **双轨持久化** — 内存热数据 + SQLite 冷存储，重启即恢复防线
- **云原生适配** — VPC 内网健康检查、云盾探针自动豁免，拒绝误报

---

## 🏗️ 系统架构 | Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     PortSentinel Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐     │
│   │  网络流量层   │───▶│  Go 侦测引擎  │───▶│  威胁判定核心  │     │
│   │  (raw socket) │    │  (eBPF/net)  │    │  (规则引擎)   │     │
│   └──────────────┘    └──────────────┘    └──────┬───────┘     │
│                                                  │              │
│                                    ┌─────────────┼──────────┐  │
│                                    ▼             ▼          ▼  │
│                              ┌─────────┐  ┌──────────┐ ┌────┐ │
│                              │ 防火墙   │  │ 告警推送  │ │日志│ │
│                              │ 内核阻断 │  │ TG/钉钉  │ │审计│ │
│                              └─────────┘  └──────────┘ └────┘ │
│                                    │                            │
│                              ┌─────▼─────┐                     │
│                              │ 双轨存储   │                     │
│                              │ mem + SQL  │                     │
│                              └───────────┘                     │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │              Bash TUI 管控中枢 (全拟态终端)              │  │
│   └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ✨ 核心特性 | Core Features

### ⚡ 极速侦测引擎

Go 编译型二进制，零解释器开销。基于原始套接字 / eBPF 的流量捕获层，**毫秒级识别**高频端口扫描与敏感协议暴力破解行为。支持协议：

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
║   [1] 🚀 启动监控服务        [2] 🛑 停止监控服务             ║
║   [3] 🔄 重启监控服务        [4] 📊 查看运行状态             ║
║   [5] ⚙️  修改配置参数        [6] 📜 查看安全日志             ║
║   [7] 🚫 管理封禁列表        [8] 📡 配置告警通道             ║
║   [9] 🧹 清理历史数据        [0] 🚪 退出管理面板             ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║  服务状态: ✅ 运行中 | 已拦截: 1,247 次 | 今日新增: 89 次    ║
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

### 一键安装

```bash
# 克隆仓库
git clone https://github.com/your-username/PortSentinel.git
cd PortSentinel

# 赋予执行权限并运行安装向导
chmod +x port-sentinel.sh
sudo ./port-sentinel.sh install
```

安装向导将自动引导你完成以下配置：

```
╔═══════════════════════════════════════════════════════════════╗
║                   🔧 安装向导 - 配置向导                      ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║  [Step 1/5] 检测系统环境...                                   ║
║  [✓] 操作系统: Ubuntu 22.04 LTS                               ║
║  [✓] 防火墙: iptables (已检测)                                ║
║  [✓] 架构: x86_64                                             ║
║                                                               ║
║  [Step 2/5] 选择检测灵敏度                                    ║
║      (1) 低  - 宽松模式, 适合开发环境                         ║
║      (2) 中  - 平衡模式, 适合一般生产环境                     ║
║      (3) 高  - 严格模式, 适合面向公网的服务器                 ║
║                                                               ║
║  [Step 3/5] 配置监控端口                                      ║
║  [✓] 已加载默认端口: 22, 80, 443, 3306, 6379, 3389, 21      ║
║                                                               ║
║  [Step 4/5] 配置告警通道                                      ║
║      是否配置 Telegram Bot? [y/N]:                            ║
║      是否配置钉钉 Webhook? [y/N]:                             ║
║      是否配置 SMTP 邮件?   [y/N]:                             ║
║                                                               ║
║  [Step 5/5] 部署服务...                                       ║
║  [✓] Go 侦测引擎已编译并安装                                  ║
║  [✓] systemd 服务已注册                                       ║
║  [✓] SQLite 数据库已初始化                                    ║
║  [✓] 防火墙规则已加载                                         ║
║                                                               ║
║  🎉 PortSentinel 部署完成! 运行 'port-sentinel' 进入管理面板 ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
```

### 手动管理

```bash
sudo ./port-sentinel.sh          # 进入管理面板
sudo ./port-sentinel.sh start    # 启动服务
sudo ./port-sentinel.sh stop     # 停止服务
sudo ./port-sentinel.sh status   # 查看状态
sudo ./port-sentinel.sh uninstall # 完整卸载
```

---

## ⚙️ 配置参数 | Configuration

配置文件路径：`/etc/port-monitor/config.yaml`

```yaml
# ============================================================
# PortSentinel 核心配置
# ============================================================

# 检测灵敏度: low / medium / high
sensitivity: high

# 监控端口列表
ports:
  - 22      # SSH
  - 80      # HTTP
  - 443     # HTTPS
  - 3306    # MySQL
  - 6379    # Redis
  - 3389    # RDP
  - 21      # FTP

# 封禁策略 (阶梯式)
block:
  first_offense: 30m     # 首次: 30 分钟
  second_offense: 24h    # 累犯: 24 小时
  third_offense: permanent # 三犯: 永久封禁

# 防火墙后端: iptables / firewalld / nftables
firewall: iptables

# 云环境自适应
cloud:
  enabled: true
  whitelist_vpc: true        # 豁免 VPC 内网探针
  whitelist_cloud_shield: true # 豁免云盾探针

# 持久化存储
storage:
  memory_buffer: 10000       # 内存环形缓冲区大小
  sqlite_path: /var/lib/port-monitor/data.db

# 告警通道
alerts:
  telegram:
    enabled: false
    bot_token: ""
    chat_id: ""
  dingtalk:
    enabled: false
    webhook: ""
  smtp:
    enabled: false
    host: ""
    port: 465
    username: ""
    password: ""
    to: ""
```

---

## 📂 目录结构 | Directory Layout

```
/etc/port-monitor/                  # 配置根目录
├── config.yaml                     # 主配置文件
└── whitelist.conf                  # IP 白名单

/usr/local/bin/
└── port-sentinel                   # 主程序二进制 (Go 编译)
└── port-sentinel.sh                # TUI 管理脚本 (Bash)

/var/lib/port-monitor/
├── data.db                         # SQLite 持久化数据库
└── blocklist.dat                   # 封禁状态快照

/var/log/port-monitor/
├── sentinel.log                    # 主日志
├── attack.log                      # 攻击事件日志
└── alert.log                       # 告警推送日志
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

```bash
# 在配置向导中选择配置 Telegram，或手动编辑 config.yaml
alerts:
  telegram:
    enabled: true
    bot_token: "YOUR_BOT_TOKEN"
    chat_id: "YOUR_CHAT_ID"
```

### 钉钉 Webhook

```bash
alerts:
  dingtalk:
    enabled: true
    webhook: "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
```

### SMTP 邮件

```bash
alerts:
  smtp:
    enabled: true
    host: "smtp.example.com"
    port: 465
    username: "alert@example.com"
    password: "YOUR_PASSWORD"
    to: "admin@example.com"
```

告警示例（Telegram）：

```
🚨 PortSentinel 安全告警

攻击类型: SSH 暴力破解
源 IP: 203.0.113.42
目标端口: 22
失败尝试: 15 次 / 30 秒
处置: 已封禁 30 分钟
时间: 2026-06-20 14:23:07 CST
```

---

## 🛠️ 编译构建 | Build from Source

```bash
# 前置依赖: Go 1.21+
cd engine/
go build -ldflags="-s -w" -o port-sentinel main.go
sudo cp port-sentinel /usr/local/bin/
```

---

## 🤝 参与贡献 | Contributing

欢迎提交 Issue 和 Pull Request。请遵循以下规范：

1. Fork 本仓库并创建特性分支 (`git checkout -b feature/your-feature`)
2. 提交前确保代码通过 `go vet` 和 ShellCheck
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
