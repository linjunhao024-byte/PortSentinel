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

# 创建目录结构，并建一个固定的非 root 运行用户。
# UID/GID 10001 与 docker-compose.yml 的 user: "10001:10001" 保持一致；
# 数据/日志目录归该用户所有，配置目录只读挂载即可。
RUN mkdir -p /etc/port-monitor \
    /var/lib/port-monitor \
    /var/log/port-monitor \
    && addgroup -g 10001 -S portsentinel \
    && adduser -u 10001 -S -G portsentinel -h /var/lib/port-monitor portsentinel \
    && chown -R portsentinel:portsentinel \
        /var/lib/port-monitor /var/log/port-monitor

# 复制引擎
COPY port-monitor /usr/local/bin/port-monitor
RUN chmod +x /usr/local/bin/port-monitor

# 默认配置（可通过挂载覆盖）
COPY config.example.yaml /etc/port-monitor/config.yaml

# 数据和日志持久化
VOLUME ["/etc/port-monitor", "/var/lib/port-monitor", "/var/log/port-monitor"]

# 需要网络权限（抓包 + 防火墙规则）
# 运行时需要 --cap-add=NET_ADMIN --cap-add=NET_RAW；host 网络用于抓真实流量。
# 容器默认以非 root 用户运行；iptables/nft 通过 capabilities 授权，不依赖 root。
EXPOSE 8900

USER portsentinel
ENTRYPOINT ["python3", "/usr/local/bin/port-monitor"]
CMD ["-config", "/etc/port-monitor/config.yaml"]
