FROM python:3.11-alpine

LABEL maintainer="LIN"
LABEL description="LIN-PortSentinel - Port Security Monitor Engine"
LABEL version="1.0.3"
LABEL org.opencontainers.image.source="https://github.com/linjunhao024-byte/PortSentinel"

# 只装运行期真正需要的东西：引擎是纯 Python 实现，
# 抓包走 AF_PACKET、告警走 urllib，不需要 bash/sqlite CLI/curl/硬件查询工具
RUN apk add --no-cache \
    iptables \
    ip6tables \
    nftables

# 创建目录结构
RUN mkdir -p /etc/port-monitor \
    /var/lib/port-monitor \
    /var/log/port-monitor

# 复制引擎
COPY port-monitor /usr/local/bin/port-monitor
RUN chmod +x /usr/local/bin/port-monitor

# 默认配置（可通过挂载覆盖）
COPY config.example.yaml /etc/port-monitor/config.yaml

# 数据和日志持久化
VOLUME ["/etc/port-monitor", "/var/lib/port-monitor", "/var/log/port-monitor"]

# 需要网络权限（抓包 + 防火墙规则）
# 运行时需要 --privileged 或 --cap-add=NET_ADMIN --cap-add=NET_RAW
EXPOSE 8900

ENTRYPOINT ["python3", "/usr/local/bin/port-monitor"]
CMD ["-config", "/etc/port-monitor/config.yaml"]
