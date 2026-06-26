<div align="center">

# LIN-PortSentinel 使用教程

**Your Ports, Our Watch.**

从零开始，一步步教你部署和使用 PortSentinel

</div>

---

## 📑 目录

- [一、快速安装](#一快速安装)
- [二、管理面板](#二管理面板)
- [三、核心功能详解](#三核心功能详解)
  - [3.1 端口扫描检测](#31-端口扫描检测)
  - [3.2 暴力破解防御](#32-暴力破解防御)
  - [3.3 DDoS 攻击检测](#33-ddos-攻击检测)
  - [3.4 蜜罐端口](#34-蜜罐端口)
  - [3.5 自适应阈值](#35-自适应阈值)
- [四、告警配置](#四告警配置)
  - [4.1 Telegram Bot](#41-telegram-bot)
  - [4.2 钉钉 Webhook](#42-钉钉-webhook)
  - [4.3 邮件 SMTP](#43-邮件-smtp)
  - [4.4 企业微信](#44-企业微信)
  - [4.5 飞书](#45-飞书)
  - [4.6 Slack](#46-slack)
  - [4.7 测试告警](#47-测试告警)
- [五、Web 仪表盘](#五web-仪表盘)
- [六、API 接口](#六api-接口)
- [七、数据导出与监控](#七数据导出与监控)
  - [7.1 CSV/JSON 导出](#71-csvjson-导出)
  - [7.2 Prometheus 指标](#72-prometheus-指标)
- [八、IP 溯源查询](#八ip-溯源查询)
- [九、白名单管理](#九白名单管理)
- [十、报告中心](#十报告中心)
- [十一、分布式联动](#十一分布式联动)
- [十二、威胁情报](#十二威胁情报)
- [十三、攻击关联分析](#十三攻击关联分析)
- [十四、自定义响应动作](#十四自定义响应动作)
- [十五、无人驾驶模式](#十五无人驾驶模式)
- [十六、配置热加载](#十六配置热加载)
- [十七、Docker 部署](#十七docker-部署)
- [十八、常见问题 FAQ](#十八常见问题-faq)

---

## 一、快速安装

### 1.1 系统要求

| 项目 | 最低要求 |
|------|---------|
| 操作系统 | Linux（Debian/Ubuntu/CentOS/Arch） |
| Python | 3.7+ |
| 权限 | root |
| 内存 | 64MB+ |
| 磁盘 | 100MB+ |

### 1.2 安装依赖

```bash
# Debian / Ubuntu
apt install python3 sqlite3 curl iptables openssl

# CentOS / RHEL / AlmaLinux
yum install python3 sqlite curl iptables openssl

# Arch Linux
pacman -S python sqlite curl iptables openssl
```

### 1.3 一键安装

```bash
# 方式一：一行命令（推荐）
wget -qO port-monitor https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor && \
wget -qO port-monitor.sh https://raw.githubusercontent.com/linjunhao024-byte/PortSentinel/main/port-monitor.sh && \
chmod +x port-monitor && \
sed -i 's/\r$//' port-monitor.sh && \
sudo bash port-monitor.sh install
```

```bash
# 方式二：Git 克隆
git clone https://github.com/linjunhao024-byte/PortSentinel.git
cd PortSentinel
sudo bash port-monitor.sh install
```

### 1.4 安装向导

安装过程会引导你完成 5 步配置：

```
步骤 1/5: 服务器环境
  [1] 云服务器 - 自动忽略内网流量，避免误报
  [2] 独立服务器/VPS - 监控全部流量

步骤 2/5: 告警通道
  [1] Telegram
  [2] 钉钉
  [3] 邮件
  [4] 全部配置

步骤 3/5: 检测灵敏度
  [1] 严格 - 10端口/10秒, 3次SSH/分钟
  [2] 正常 - 20端口/10秒, 5次SSH/分钟 [推荐]
  [3] 宽松 - 50端口/10秒, 10次SSH/分钟

步骤 4/5: 无人驾驶模式
  启用后系统将自动：
    • 定期健康检查 + 自动修复
    • 每天自动清理过期数据
    • 每天自动备份
    • 检测新版本并自动更新

步骤 5/5: 确认安装
```

### 1.5 安装完成后

```bash
# 快捷命令
pm              # 打开管理面板
pm start        # 启动服务
pm stop         # 停止服务
pm status       # 查看状态
pm --version    # 查看版本
```

---

## 二、管理面板

运行 `pm` 进入管理面板：

```
  +========================================================+
  |                                                        |
  |           ####           ##          ##   ##           |
  |           ####           ##          ###  ##           |
  |           ####           ##          #### ##           |
  |           ####           ##          ## ####           |
  |           ####           ##          ##  ###           |
  |           ####           ##          ##   ##           |
  |           ########       ##          ##   ##           |
  |                                                        |
  |========================================================|
  |                P O R T S E N T I N E L                 |
  |                  Your Ports, Our Watch.                 |
  +========================================================+

╔══════════════════════════════════════════════════════════════╗
║  LIN-PortSentinel v1.0.2  │ 主机: web-server  │ 运行: 2h    ║
║  CPU: 2%  │ 内存: 1%  │ 状态: 运行中      ║
╚══════════════════════════════════════════════════════════════╝

  服务控制
  [ 1] 启动服务       [ 2] 停止服务       [ 3] 重启服务
  [ 4] 热加载配置

  监控查询
  [ 5] 查看状态       [ 6] 查看统计       [ 7] 查看封禁IP
  [ 8] 查看日志       [ 9] 实时监控       [10] IP溯源查询

  告警报告
  [11] 测试告警       [12] 报告中心       [13] 健康检查

  数据与面板
  [14] Web仪表盘      [15] 导出数据       [16] Prometheus指标

  系统维护
  [17] 手动解封       [18] 白名单管理     [19] 编辑配置
  [20] 更新程序       [21] 备份配置       [22] 日志清理
  [ 0] 退出
```

### 功能速查表

| 编号 | 功能 | 说明 |
|:---:|------|------|
| 1 | 启动服务 | 启动检测引擎 |
| 2 | 停止服务 | 停止检测引擎 |
| 3 | 重启服务 | 重启引擎（配置生效） |
| 4 | 热加载配置 | 修改配置后无需重启，直接加载 |
| 5 | 查看状态 | 显示服务运行状态 |
| 6 | 查看统计 | 显示 CPU/内存/包处理数 |
| 7 | 查看封禁IP | 列出所有被封禁的 IP |
| 8 | 查看日志 | 实时滚动日志 |
| 9 | 实时监控 | 全屏攻击监控面板 |
| 10 | IP溯源查询 | 查询 IP 归属地/威胁等级 |
| 11 | 测试告警 | 测试告警通道是否正常 |
| 12 | 报告中心 | 查看/发送/定时攻击报告 |
| 13 | 健康检查 | 一键检查 8 项系统状态 |
| 14 | Web仪表盘 | 打开浏览器可视化面板 |
| 15 | 导出数据 | 导出 CSV/JSON 攻击数据 |
| 16 | Prometheus指标 | 显示 Prometheus 端点信息 |
| 17 | 手动解封 | 手动解封指定 IP |
| 18 | 白名单管理 | 添加/删除白名单 IP |
| 19 | 编辑配置 | 用编辑器修改配置文件 |
| 20 | 更新程序 | 从 GitHub 下载最新版本 |
| 21 | 备份配置 | 打包配置和数据 |
| 22 | 日志清理 | 清理过期日志和数据 |

---

## 三、核心功能详解

### 3.1 端口扫描检测

**原理**：监控 TCP SYN 包，统计每个源 IP 在滑动窗口内连接的不同端口数量。

**阈值级别**：

| 级别 | 默认阈值 | 行为 |
|------|---------|------|
| LOW | 10 端口/10秒 | 仅告警，不封禁 |
| MEDIUM | 20 端口/10秒 | 告警 + 封禁 1h |
| HIGH | 100 端口/10秒 | 告警 + 封禁 2h |
| CRITICAL | 1000 端口/10秒 | 告警 + 封禁 5h |

**配置**：

```yaml
rules:
  port_scan:
    window: 10s           # 检测窗口
    thresholds:
      low: 10             # 仅告警
      medium: 20          # 触发封禁
      high: 100           # 封禁时长 ×2
      critical: 1000      # 封禁时长 ×5
    auto_ban: true         # 自动封禁
    ban_duration: 1h       # 基础封禁时长
```

**调整建议**：
- 云服务器建议设 `medium: 30`（内网流量大）
- 独立服务器建议设 `medium: 15`（更敏感）

---

### 3.2 暴力破解防御

**原理**：监控敏感端口（SSH/MySQL/Redis 等）的连接频率，超过阈值即封禁。

**默认配置**：

```yaml
rules:
  brute_force:
    window: 60s
    auto_ban: true
    ban_duration: 24h
    permanent: false        # true = 永久封禁
    sensitive_ports:
      - port: 22
        name: "SSH"
        threshold: 5        # 60秒内 5 次
      - port: 3306
        name: "MySQL"
        threshold: 10
      - port: 6379
        name: "Redis"
        threshold: 3
```

**添加自定义端口**：

```yaml
sensitive_ports:
  - port: 2222
    name: "SSH-自定义"
    threshold: 5
  - port: 5432
    name: "PostgreSQL"
    threshold: 10
  - port: 27017
    name: "MongoDB"
    threshold: 3
```

---

### 3.3 DDoS 攻击检测

**原理**：监控单个源 IP 的 SYN 包速率，超过阈值即封禁。

```yaml
rules:
  ddos:
    window: 5s
    threshold: 1000         # 5秒内 1000 个 SYN 包
    auto_ban: true
    ban_duration: 1h
```

**注意**：这是单源 IP 检测。分布式 DDoS（每个源 IP 速率低但总量高）需要配合云厂商防护。

---

### 3.4 蜜罐端口

**原理**：开放诱饵端口，任何连接立即封禁（零容忍）。

```yaml
honeypot:
  enabled: true
  ports:
    - 2222                  # 假 SSH
    - 8888                  # 假 HTTP
    - 33899                 # 假 RDP
  ban_duration: 7d
  permanent: false
  services:                 # 协议模拟（可选）
    "2222": "ssh"           # 返回 SSH banner
    "8888": "http"          # 返回假登录页
    "33899": "redis"        # 返回 Redis 响应
```

**使用场景**：
- 扫描器经常探测非标准端口
- 任何连接这些端口的都是恶意行为
- 可以捕获攻击者的扫描工具指纹

---

### 3.5 自适应阈值

**原理**：学习期自动采集流量基线，动态调整检测灵敏度。

```yaml
rules:
  adaptive:
    enabled: true
    learning_period: 30m    # 学习期时长
    multiplier: 3.0         # 阈值 = 基线 × 3.0
    anomaly_factor: 10.0    # 流量突增 10 倍告警
    recalibrate_interval: 1h
```

**适用场景**：
- 流量波动大的环境（如电商促销）
- 白天流量高、凌晨流量低
- 减少误报

---

## 四、告警配置

### 4.1 Telegram Bot

**步骤**：

1. 在 Telegram 搜索 `@BotFather`，发送 `/newbot` 创建机器人
2. 获取 Bot Token（格式：`123456:ABC-DEF...`）
3. 搜索 `@userinfobot` 获取你的 Chat ID
4. 配置：

```yaml
alert:
  telegram:
    enabled: true
    bot_token: "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11"
    chat_id: "987654321"
```

---

### 4.2 钉钉 Webhook

**步骤**：

1. 打开钉钉群 → 设置 → 智能群助手 → 添加机器人
2. 选择「自定义」→ 安全设置选择「加签」
3. 复制 Webhook 地址和签名密钥

```yaml
alert:
  dingtalk:
    enabled: true
    webhook: "https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN"
    secret: "SEC_YOUR_SECRET"    # 可选，签名密钥
```

---

### 4.3 邮件 SMTP

**支持的邮箱**：

| 邮箱 | SMTP 服务器 | 端口 |
|------|------------|------|
| QQ 邮箱 | smtp.qq.com | 465 |
| 163 邮箱 | smtp.163.com | 465 |
| Gmail | smtp.gmail.com | 587 |
| 自定义 | 你的服务器 | 465/587 |

**QQ 邮箱配置示例**：

1. 登录 QQ 邮箱 → 设置 → 账户 → 开启 SMTP 服务
2. 生成授权码（不是 QQ 密码）

```yaml
alert:
  email:
    enabled: true
    smtp_host: "smtp.qq.com"
    smtp_port: 465
    username: "your@qq.com"
    password: "你的授权码"      # 不是 QQ 密码
    to: "admin@example.com"
```

---

### 4.4 企业微信

1. 企业微信 → 应用管理 → 创建应用
2. 获取 Webhook 地址

```yaml
alert:
  wechat:
    enabled: true
    webhook: "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY"
```

---

### 4.5 飞书

1. 飞书群 → 设置 → 群机器人 → 添加机器人
2. 选择「自定义机器人」→ 复制 Webhook 地址

```yaml
alert:
  feishu:
    enabled: true
    webhook: "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK"
    secret: "YOUR_SECRET"    # 可选
```

---

### 4.6 Slack

1. Slack → Apps → Incoming Webhooks → 添加
2. 选择频道 → 复制 Webhook URL

```yaml
alert:
  slack:
    enabled: true
    webhook: "https://hooks.slack.com/services/T00/B00/XXXX"
```

---

### 4.7 测试告警

配置完成后，测试告警通道：

```bash
pm                    # 进入管理面板
# 选择 [11] 测试告警

# 或直接命令
sudo port-monitor.sh test-alert
```

---

## 五、Web 仪表盘

### 5.1 启用 API

```yaml
api:
  enabled: true              # 必须启用
  host: "0.0.0.0"            # 监听地址
  port: 8900                 # 监听端口
  token: "your-secure-token" # API 认证令牌
```

### 5.2 访问仪表盘

```bash
# 重启服务使配置生效
pm restart

# 查看仪表盘地址
pm
# 选择 [14] Web仪表盘
```

浏览器打开 `http://你的服务器IP:8900/`

### 5.3 仪表盘功能

- **顶部状态栏**：服务状态、CPU、内存、包处理数
- **核心指标**：总攻击、已封禁、唯一 IP、情报缓存
- **攻击趋势图**：7 天柱状图（按类型分色）
- **最近攻击表**：分页浏览
- **攻击源 TOP10**：按次数排序
- **封禁列表**：管理所有封禁 IP

---

## 六、API 接口

所有 API 需要在请求头携带 Token：

```bash
curl -H "Authorization: Bearer your-token" http://localhost:8900/api/status
```

### 端点列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/status` | 服务状态 |
| GET | `/api/bans` | 封禁列表 |
| GET | `/api/stats` | 攻击统计 |
| GET | `/api/health` | 健康检查 |
| GET | `/api/timeseries` | 7天趋势数据 |
| GET | `/api/history?page=1&limit=20` | 分页攻击历史 |
| GET | `/api/threat-intel?ip=1.2.3.4` | 威胁情报查询 |
| GET | `/api/export/csv?days=30` | CSV 导出 |
| GET | `/api/export/json?days=30` | JSON 导出 |
| GET | `/api/metrics` | Prometheus 指标 |
| GET | `/api/correlation` | 关联分析事件 |
| GET | `/api/cluster` | 集群状态 |
| POST | `/api/ban` | 手动封禁 |
| POST | `/api/unban` | 解封 |
| POST | `/api/sync` | 集群封禁同步 |

### 示例

```bash
# 查看状态
curl -H "Authorization: Bearer TOKEN" http://localhost:8900/api/status

# 手动封禁 IP
curl -X POST -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ip":"1.2.3.4","duration":"24h"}' \
  http://localhost:8900/api/ban

# 解封 IP
curl -X POST -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ip":"1.2.3.4"}' \
  http://localhost:8900/api/unban
```

---

## 七、数据导出与监控

### 7.1 CSV/JSON 导出

```bash
pm                    # 进入管理面板
# 选择 [15] 导出数据

# 或直接命令
sudo port-monitor.sh export
```

导出文件保存在当前目录：`port-sentinel-export-20260627_120000.csv`

### 7.2 Prometheus 指标

配置 Prometheus 抓取：

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'portsentinel'
    static_configs:
      - targets: ['your-server:8900']
    metrics_path: '/api/metrics'
    params:
      token: ['your-token']
```

**可用指标**：

| 指标名 | 类型 | 说明 |
|--------|------|------|
| `portsentinel_blocked_ips` | gauge | 当前封禁 IP 数量 |
| `portsentinel_attacks_total` | counter | 攻击总数（按类型） |
| `portsentinel_uptime_seconds` | gauge | 运行时长 |
| `portsentinel_packets_total` | gauge | 处理包数 |
| `portsentinel_ban_hits_total` | gauge | 封禁拦截次数 |

---

## 八、IP 溯源查询

```bash
pm                    # 进入管理面板
# 选择 [10] IP溯源查询

# 或直接命令
sudo port-monitor.sh lookup 185.220.101.34
```

**输出示例**：

```
╔══════════════════════════════════════════════════════════╗
║  🔍 IP 溯源报告: 185.220.101.34                          ║
╠══════════════════════════════════════════════════════════╣
║  反向 DNS:  tor-exit-34.example.net                      ║
║  国家/地区: 德国                                          ║
║  运营商:    Tor Exit Node Operator                        ║
║  ASN:       AS12345 Tor Exit Network                     ║
╠══════════════════════════════════════════════════════════╣
║  本地攻击记录                                             ║
║  总攻击:    1523 次                                       ║
║  近24小时:  89 次                                         ║
║  攻击类型:  brute_force, port_scan                       ║
╠══════════════════════════════════════════════════════════╣
║  当前封禁:  是                                            ║
║  威胁等级:  极高                                          ║
╚══════════════════════════════════════════════════════════╝
```

---

## 九、白名单管理

```bash
pm                    # 进入管理面板
# 选择 [18] 白名单管理
```

**操作**：
- `a` — 添加 IP 或 CIDR（如 `10.0.0.0/8`）
- `r` — 删除条目（输入编号）
- `s` — 热加载生效
- `q` — 返回

**内置白名单**（自动生效）：
- `127.0.0.1`（本地回环）
- `::1`（IPv6 本地回环）
- `10.0.0.0/8`（内网，云服务器模式）
- `172.16.0.0/12`（内网，云服务器模式）
- `192.168.0.0/16`（内网，云服务器模式）

---

## 十、报告中心

```bash
pm                    # 进入管理面板
# 选择 [12] 报告中心
```

**功能**：
1. **查看报告** — 终端显示攻击统计
2. **发送报告** — 通过告警通道发送
3. **定时报告** — 设置 cron 自动发送

**定时报告类型**：
- 日报（每天 09:00）
- 周报（每周一 09:00）
- 月报（每月 1 日 09:00）
- 自定义 cron

**报告内容**：
- 核心指标 + 环比分析
- 攻击类型分布
- 高危端口 TOP5
- 攻击时段分布（ASCII 柱状图）
- 攻击源 TOP8
- 最近攻击记录

---

## 十一、分布式联动

多台服务器共享封禁列表，一台检测到攻击，所有节点同步封禁。

### 配置主节点

```yaml
api:
  enabled: true
  host: "0.0.0.0"
  port: 8900
  token: "shared-secret"

federation:
  enabled: true
  sync_interval: 60s
  node_id: "node-1"
  cluster_secret: "cluster-shared-secret"
  peers:
    - url: "http://10.0.0.2:8900"
      token: "shared-secret"
    - url: "http://10.0.0.3:8900"
      token: "shared-secret"
```

### 配置从节点

```yaml
api:
  enabled: true
  host: "0.0.0.0"
  port: 8900
  token: "shared-secret"

federation:
  enabled: true
  sync_interval: 60s
  node_id: "node-2"
  cluster_secret: "cluster-shared-secret"
  peers:
    - url: "http://10.0.0.1:8900"
      token: "shared-secret"
```

---

## 十二、威胁情报

集成公开威胁情报源，自动识别恶意 IP。

```yaml
threat_intel:
  enabled: true
  # AbuseIPDB API Key（可选）
  # 注册 https://www.abuseipdb.com/ 获取
  abuseipdb_key: ""
  sync_interval: 6h
```

**数据源**：
- FireHol Level 1/2 黑名单（~10 万条 CIDR）
- AbuseIPDB 信誉查询（需 API Key）

**效果**：
- 封禁时自动查询 IP 信誉
- 高风险 IP 自动延长封禁时长
- 仪表盘显示威胁情报缓存数量

---

## 十三、攻击关联分析

追踪同一 IP 的多阶段攻击行为，自动聚合告警。

```yaml
correlation:
  enabled: true
  window: 10m    # 关联时间窗口
```

**检测逻辑**：
- 同一 IP 在 10 分钟内出现 2 种以上攻击类型 → 多阶段攻击告警
- 同一 IP 在 10 分钟内累计 10+ 次攻击 → 持续攻击告警

**示例**：
```
14:00 - 扫描 22,3306,6379 端口（port_scan）
14:02 - 暴力破解 SSH 5 次（brute_force）
→ 触发：🔗 关联告警 - 多阶段攻击: brute_force+port_scan
```

---

## 十四、自定义响应动作

检测到攻击时自动执行 Webhook 或脚本。

```yaml
response:
  enabled: true
  actions:
    # Webhook 通知
    - type: webhook
      url: "https://internal.example.com/api/security-event"
      method: POST
      body: '{"ip":"{{src_ip}}","type":"{{attack_type}}","port":{{dst_port}}}'

    # 脚本执行
    - type: script
      path: "/opt/scripts/notify-soc.sh"
      args: ["{{src_ip}}", "{{attack_type}}"]
```

**可用变量**：
- `{{src_ip}}` — 攻击源 IP
- `{{attack_type}}` — 攻击类型
- `{{dst_port}}` — 目标端口
- `{{duration}}` — 封禁时长
- `{{time}}` — 时间
- `{{hostname}}` — 主机名

---

## 十五、无人驾驶模式

安装时选择启用后，系统完全自治。

```yaml
autopilot:
  enabled: true
  # 健康监控
  health_check_interval: 5m
  max_restart_attempts: 3
  restart_cooldown: 60s
  # 自动清理
  auto_cleanup: true
  cleanup_interval: 24h
  cleanup_keep_days: 30
  # 自动备份
  auto_backup: true
  backup_interval: 24h
  backup_keep_count: 7
  backup_dir: "/var/lib/port-monitor/backups"
  # 自动更新
  auto_update: true
  update_check_interval: 12h
  auto_update_apply: true
```

**自动修复能力**：

| 问题 | 自动修复 |
|------|---------|
| 数据库损坏 | 重建连接 |
| 防火墙规则丢失 | 恢复封禁规则 |
| 磁盘空间不足 | 自动清理旧数据 |
| 抓包线程异常 | 记录告警 |

---

## 十六、配置热加载

修改配置后无需重启服务：

```bash
pm                    # 进入管理面板
# 选择 [4] 热加载配置

# 或直接命令
sudo port-monitor.sh reload
```

**热加载范围**：
- ✅ 检测阈值
- ✅ 白名单
- ✅ 告警配置
- ✅ 蜜罐端口
- ✅ 自适应参数
- ✅ 告警模板
- ❌ API 端口（需重启）
- ❌ 数据库路径（需重启）

---

## 十七、Docker 部署

### 构建镜像

```bash
git clone https://github.com/linjunhao024-byte/PortSentinel.git
cd PortSentinel
docker build -t portsentinel .
```

### 运行容器

```bash
docker run -d \
  --name port-sentinel \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  -v $(pwd)/config:/etc/port-monitor:ro \
  -v portsentinel-data:/var/lib/port-monitor \
  -v portsentinel-logs:/var/log/port-monitor \
  portsentinel
```

### Docker Compose

```bash
docker-compose up -d
```

**注意**：
- 必须使用 `--network host` 才能抓取真实流量
- 必须添加 `NET_ADMIN` 和 `NET_RAW` 权限
- 配置文件挂载到 `/etc/port-monitor/config.yaml`

---

## 十八、常见问题 FAQ

### Q1: 安装后没有反应？

```bash
# 检查服务状态
pm status

# 查看日志
pm logs

# 检查是否以 root 运行
sudo pm start
```

### Q2: 没有收到告警？

```bash
# 测试告警通道
sudo port-monitor.sh test-alert

# 检查配置文件
cat /etc/port-monitor/config.yaml | grep -A5 "alert:"

# 确认 enabled 为 true
```

### Q3: 误封了正常 IP？

```bash
# 查看封禁列表
pm
# 选择 [7] 查看封禁IP

# 手动解封
pm
# 选择 [17] 手动解封

# 或直接命令
sudo port-monitor.sh unban
```

### Q4: 如何添加白名单？

```bash
pm
# 选择 [18] 白名单管理
# 输入 a 添加，输入 IP 或 CIDR
```

### Q5: 内存占用过高？

```yaml
# 调低追踪上限
storage:
  memory:
    max_items: 50000    # 默认 100000
```

### Q6: 如何查看实时攻击？

```bash
pm
# 选择 [9] 实时监控

# 或直接命令
sudo port-monitor.sh live
```

### Q7: 如何导出攻击数据？

```bash
pm
# 选择 [15] 导出数据

# 或直接命令
sudo port-monitor.sh export
```

### Q8: 如何更新到最新版本？

```bash
pm
# 选择 [20] 更新程序

# 或直接命令
sudo port-monitor.sh update
```

如果开启了无人驾驶模式，会自动检查并更新。

### Q9: 如何完全卸载？

```bash
sudo port-monitor.sh full-uninstall
```

### Q10: 支持 IPv6 吗？

完全支持。IPv6 抓包、解析、封禁、白名单全部支持。

### Q11: 性能开销大吗？

| 场景 | CPU | 内存 |
|------|-----|------|
| 小型 VPS | <1% | 25 MB |
| 中型服务器 | 1-3% | 35 MB |
| 大型服务器 | 3-8% | 60 MB |

### Q12: 配置文件在哪里？

```
/etc/port-monitor/config.yaml    # 主配置
/var/lib/port-monitor/monitor.db # 数据库
/var/log/port-monitor/           # 日志
```

---

<div align="center">

**LIN-PortSentinel** — *Your Ports, Our Watch.*

有问题？[提交 Issue](https://github.com/linjunhao024-byte/PortSentinel/issues)

</div>
