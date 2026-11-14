#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""t26 离线测试：PortSentinel 七条「运行期/规则」P2。

全程离线：subprocess 全部被 FakeSubprocess 接管（只记录 argv，绝不执行任何
真实 iptables/nft/安装脚本）；sqlite 一律用临时文件；API handler 用
object.__new__ 构造，不监听端口、不发请求。

跑法：python tests/_ps_p2a_tests.py   （全部 PASS 时退出码 0）
"""
import email.message
import io
import logging
import os
import shutil
import sys
import tempfile
import traceback
import types

try:  # Windows 控制台默认 GBK，中文断言信息会炸
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
ENGINE = os.path.join(BASE, "port-monitor")
SRC = io.open(ENGINE, encoding="utf-8", newline="").read()


# ── 引擎加载 ────────────────────────────────────────────────
def load_engine(env=None):
    """把无扩展名引擎 exec 进一个干净模块；env 用于测环境变量读取。"""
    saved = {}
    if env:
        for k, v in env.items():
            saved[k] = os.environ.get(k)
            os.environ[k] = v
    try:
        mod = types.ModuleType("port_monitor_under_test")
        mod.__file__ = ENGINE
        exec(compile(SRC, ENGINE, "exec"), mod.__dict__)
        return mod
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


# ── 假子进程 ────────────────────────────────────────────────
class Result(object):
    def __init__(self, returncode=0, stdout="", stderr="", text=False):
        self.returncode = returncode
        self.stdout = stdout if text else stdout.encode()
        self.stderr = stderr if text else stderr.encode()
        self.args = []


class FakeSubprocess(object):
    """记录所有 argv；按规则返回码。绝不执行真实命令。"""

    def __init__(self, real=None):
        self.real = real
        self.calls = []
        self.table_exists = True
        self.chain_exists = True
        self.table_add_ok = True
        self.chain_add_ok = True
        self.chain_add_ignored = False   # add chain 报成功但 list 仍然查不到
        self.rule_exists = False         # iptables -C 的结果
        self.add_rule_ok = True
        self.delete_table_ok = True
        self.fail_contains = []          # argv 里出现这些子串就 rc=1
        self.sweep_output = ""           # iptables -S INPUT 的输出

    def __getattr__(self, name):
        if self.real is not None:
            return getattr(self.real, name)
        raise AttributeError(name)

    # 便捷查询
    def argv_of(self, *prefix):
        prefix = list(prefix)
        return [c for c in self.calls if c[:len(prefix)] == prefix]

    def iptables_calls(self):
        return [c for c in self.calls if c and c[0] in ("iptables", "ip6tables")]

    def run(self, argv, **kwargs):
        argv = [str(a) for a in argv]
        self.calls.append(argv)
        text = bool(kwargs.get("text"))
        rc, out, err = self._decide(argv)
        return Result(rc, out, err, text)

    def _decide(self, argv):
        joined = " ".join(argv)
        for needle in self.fail_contains:
            if needle in joined:
                return 1, "", "fake failure for %r" % needle
        if argv[:1] == ["nft"]:
            if "list" in argv and "table" in argv:
                return (0 if self.table_exists else 1), "", ""
            if "list" in argv and "chain" in argv:
                if "-a" in argv:            # unban 时列规则
                    return 0, "", ""
                return (0 if self.chain_exists else 1), "", ""
            if "add" in argv and "table" in argv:
                if not self.table_add_ok:
                    return 1, "", "add table failed"
                self.table_exists = True
                return 0, "", ""
            if "add" in argv and "chain" in argv:
                if not self.chain_add_ok:
                    return 1, "", "add chain failed"
                if not self.chain_add_ignored:
                    self.chain_exists = True
                return 0, "", ""
            if "add" in argv and "rule" in argv:
                return (0 if self.add_rule_ok else 1), "", ""
            if "delete" in argv and "table" in argv:
                if not self.delete_table_ok:
                    return 1, "", "delete table failed"
                self.table_exists = False
                return 0, "", ""
            return 0, "", ""
        if argv[0] in ("iptables", "ip6tables"):
            if "-S" in argv:
                return 0, self.sweep_output, ""
            if "-C" in argv:
                return (0 if self.rule_exists else 1), "", ""
            return 0, "", ""
        if argv[0] in ("firewall-cmd",):
            return 0, "", ""
        return 0, "", ""


def install_fake(mod, fake):
    mod.subprocess = fake


# ── 日志捕获 ────────────────────────────────────────────────
class _Collect(logging.Handler):
    def __init__(self):
        logging.Handler.__init__(self)
        self.messages = []

    def emit(self, record):
        try:
            self.messages.append(record.getMessage())
        except Exception:
            self.messages.append(str(record.msg))


class capture_logs(object):
    def __init__(self, mod):
        self.logger = mod.logger
        self.collect = _Collect()

    def __enter__(self):
        self.old_level = self.logger.level
        self.logger.setLevel(logging.DEBUG)
        self.logger.addHandler(self.collect)
        return self.collect.messages

    def __exit__(self, *exc):
        self.logger.removeHandler(self.collect)
        self.logger.setLevel(self.old_level)
        return False


# ── 小工具 ──────────────────────────────────────────────────
def make_handler(mod, path="/api/stats", token="secret-token", headers=None):
    """构造一个不连套接字的 APIHandler（只测认证/分页逻辑）。"""
    h = object.__new__(mod.APIHandler)
    h.api_token = token
    h.path = path
    msg = email.message.Message()
    for k, v in (headers or {}).items():
        msg[k] = v
    h.headers = msg
    h.responses = []
    h._respond = lambda code, data: h.responses.append((code, data))
    return h


class StubDB(object):
    def __init__(self, rows=(), one=(0,), dropped=0):
        self.calls = []
        self._rows = list(rows)
        self._one = one
        self.dropped_total = dropped
        self.conn = None

    def fetchone(self, sql, params=()):
        self.calls.append(("fetchone", sql, tuple(params)))
        return self._one

    def fetchall(self, sql, params=()):
        self.calls.append(("fetchall", sql, tuple(params)))
        return self._rows


class StubEngine(object):
    def __init__(self, db):
        self.db = db


def tmpdir():
    return tempfile.mkdtemp(prefix="ps_p2a_")


# ══════════════════════════════════════════════════════════
# 第 1 条：iptables 统一走 _iptables，自动补 -w
# ══════════════════════════════════════════════════════════
def test_iptables_wrapper_injects_wait():
    m = load_engine()
    fake = FakeSubprocess()
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    res = fw._iptables(["iptables", "-I", "INPUT", "1", "-s", "1.2.3.4",
                        "-j", "DROP"])
    assert res is not None and res.returncode == 0, "包装应返回成功结果"
    got = fake.calls[-1]
    assert got[:3] == ["iptables", "-w", "5"], "应自动注入 -w 5，实际 %r" % (got,)


def test_iptables_wrapper_respects_existing_wait():
    m = load_engine()
    fake = FakeSubprocess()
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    fw._iptables(["iptables", "-w", "9", "-D", "INPUT", "-s", "1.2.3.4",
                  "-j", "DROP"])
    got = fake.calls[-1]
    assert got.count("-w") == 1, "已有 -w 不应重复注入：%r" % (got,)
    assert got[1] == "-w" and got[2] == "9", "应保留调用方给的等待秒数：%r" % (got,)


def test_iptables_wait_configurable():
    m = load_engine()
    fake = FakeSubprocess()
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    fw.iptables_wait = 12
    fw._iptables(["iptables", "-L", "-n"])
    assert fake.calls[-1][1:3] == ["-w", "12"], "应使用实例配置的等待秒数"
    m2 = load_engine({"PORTSENTINEL_IPTABLES_WAIT": "7"})
    assert m2.IPTABLES_WAIT == 7, "环境变量应能覆盖默认 -w 值，实际 %r" % (
        m2.IPTABLES_WAIT,)


def test_iptables_wrapper_warns_on_failure():
    m = load_engine()
    fake = FakeSubprocess()
    fake.fail_contains = ["-I"]
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    with capture_logs(m) as logs:
        res = fw._iptables(["iptables", "-I", "INPUT", "1", "-s", "1.2.3.4",
                            "-j", "DROP"])
    assert res is not None and res.returncode == 1, "失败也要返回结果对象"
    assert any("rc=1" in x for x in logs), "失败必须记 WARN，实际 %r" % (logs,)


def test_ban_all_calls_have_wait():
    m = load_engine()
    fake = FakeSubprocess()
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    assert fw.ban("1.2.3.4") is True, "正常封禁应成功"
    calls = fake.iptables_calls()
    assert calls, "应产生 iptables 调用"
    for c in calls:
        assert "-w" in c, "封禁路径有调用没带 -w：%r" % (c,)


def test_unban_all_calls_have_wait():
    m = load_engine()
    fake = FakeSubprocess()
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    assert fw.unban("1.2.3.4") is True, "无残留时应确认解封成功"
    calls = fake.iptables_calls()
    assert calls, "应产生 iptables 调用"
    for c in calls:
        assert "-w" in c, "解封路径有调用没带 -w：%r" % (c,)


def test_ban_fails_loudly_when_iptables_fails():
    m = load_engine()
    fake = FakeSubprocess()
    fake.fail_contains = ["-I"]
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")
    with capture_logs(m) as logs:
        ok = fw.ban("5.6.7.8")
    assert ok is False, "iptables 失败时 ban() 必须返回 False（旧版静默）"
    assert any("失败" in x for x in logs), "失败必须留日志，实际 %r" % (logs,)


# ══════════════════════════════════════════════════════════
# 第 2 条：nft 表 + 链都要校验，缺则重建并复查
# ══════════════════════════════════════════════════════════
def test_nft_rebuilds_missing_chain():
    m = load_engine()
    fake = FakeSubprocess()
    fake.table_exists = True
    fake.chain_exists = False
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")
    with capture_logs(m) as logs:
        ok, err = fw._ensure_nft_checked()
    assert ok is True, "链缺失时应重建成功，err=%r" % (err,)
    assert fake.argv_of("nft", "add", "chain"), "应补建 chain"
    assert fake.chain_exists is True, "重建后链应存在"
    assert any("重建" in x for x in logs), "重建应留日志"


def test_nft_rebuilds_missing_table():
    m = load_engine()
    fake = FakeSubprocess()
    fake.table_exists = False
    fake.chain_exists = False
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")
    ok, err = fw._ensure_nft_checked()
    assert ok is True, "表链都缺时应全部重建，err=%r" % (err,)
    assert fake.argv_of("nft", "add", "table"), "应补建 table"
    assert fake.argv_of("nft", "add", "chain"), "应补建 chain"


def test_nft_reports_when_rebuild_fails():
    m = load_engine()
    fake = FakeSubprocess()
    fake.chain_exists = False
    fake.chain_add_ok = False
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")
    ok, err = fw._ensure_nft_checked()
    assert ok is False, "建链失败必须返回 False"
    assert "建立 nft 链失败" in err, "错误说明应指明建链失败，实际 %r" % (err,)
    with capture_logs(m) as logs:
        assert fw._ensure_nft() is False, "兼容包装也应返回 False"
    assert any("nftables 不可用" in x for x in logs), "应记 ERROR 日志"


def test_nft_recheck_catches_silent_chain_loss():
    m = load_engine()
    fake = FakeSubprocess()
    fake.chain_exists = False
    fake.chain_add_ignored = True     # add 报成功，但 list 仍查不到
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")
    ok, err = fw._ensure_nft_checked()
    assert ok is False, "复查必须发现链其实没建成（旧版只探表就放行）"
    assert "复查失败" in err, "错误说明应指出复查失败，实际 %r" % (err,)


def test_ban_uses_checked_nft_and_reports():
    m = load_engine()
    fake = FakeSubprocess()
    fake.chain_exists = False
    fake.chain_add_ignored = True
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")
    with capture_logs(m) as logs:
        ok = fw.ban("9.9.9.9")
    assert ok is False, "nft 不可用时 ban() 必须失败而不是假装成功"
    assert any("nftables 不可用" in x for x in logs), "应说明原因，实际 %r" % (logs,)


# ══════════════════════════════════════════════════════════
# 第 3 条：缓冲区满不再静默丢弃
# ══════════════════════════════════════════════════════════
def test_buffer_drop_counts_and_warns():
    m = load_engine()
    d = tmpdir()
    try:
        db = m.Database(os.path.join(d, "t.db"))
        db._PENDING_MAX = 3
        db._DROP_WARN_EVERY = 2
        db._DROP_WARN_INTERVAL = 0.0
        with capture_logs(m) as logs:
            results = [db.record_attack("1.1.1.1", "port_scan", 22)
                       for _ in range(5)]
        assert results == [True, True, True, False, False], \
            "前 3 条入队、后 2 条丢弃，实际 %r" % (results,)
        assert db.dropped_total == 2, "dropped_total 应为 2，实际 %r" % (
            db.dropped_total,)
        stats = db.drop_stats()
        assert stats["capacity"] == 3 and stats["dropped_total"] == 2, \
            "drop_stats 应反映上限与累计丢弃：%r" % (stats,)
        assert stats["pending"] <= 3, "待写条数不应超过上限"
        assert any("已丢弃" in x for x in logs), "丢弃必须告警，实际 %r" % (logs,)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_dropped_total_metric_exposed():
    m = load_engine()
    exp = object.__new__(m.ExportManager)
    exp.db = StubDB(dropped=7)
    text = exp.prometheus_metrics()
    assert "portsentinel_dropped_records_total 7" in text, \
        "指标应暴露丢弃累计值，实际片段：%r" % (
            [l for l in text.splitlines() if "dropped" in l],)


# ══════════════════════════════════════════════════════════
# 第 4 条：SQLite 初始化（目录 + busy_timeout）
# ══════════════════════════════════════════════════════════
def test_connect_creates_missing_directory():
    m = load_engine()
    d = tmpdir()
    try:
        target = os.path.join(d, "a", "b", "c", "x.db")
        db = m.Database(target)
        assert os.path.isdir(os.path.dirname(target)), "应自动建出目录"
        db.close() if hasattr(db, "close") else None
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_connect_sets_busy_timeout():
    m = load_engine()
    d = tmpdir()
    try:
        db = m.Database(os.path.join(d, "t.db"))
        got = db.conn.execute("PRAGMA busy_timeout").fetchone()[0]
        assert got == 10000, "busy_timeout 应为 10000，实际 %r" % (got,)
        assert m.Database._CONNECT_TIMEOUT == 10.0, "connect timeout 应为 10 秒"
    finally:
        shutil.rmtree(d, ignore_errors=True)


def test_connect_without_directory_part():
    m = load_engine()
    d = tmpdir()
    cwd = os.getcwd()
    try:
        os.chdir(d)
        db = m.Database("plain.db")     # 旧版 os.makedirs("") 直接抛错
        assert os.path.isfile(os.path.join(d, "plain.db")), "应建出库文件"
    finally:
        os.chdir(cwd)
        shutil.rmtree(d, ignore_errors=True)


# ══════════════════════════════════════════════════════════
# 第 5 条：token 只认请求头
# ══════════════════════════════════════════════════════════
def test_query_string_token_rejected():
    m = load_engine()
    h = make_handler(m, path="/api/stats?token=secret-token")
    with capture_logs(m) as logs:
        ok = h._check_auth()
    assert ok is False, "查询串里的 token 必须拒绝"
    assert "查询串" in h._auth_reason, "应给出明确文案，实际 %r" % (
        h._auth_reason,)
    assert any("查询串" in x for x in logs), "应记一条 WARN"
    for msg in logs:
        assert "secret-token" not in msg, "日志不能打印 token 本身：%r" % (msg,)


def test_header_token_accepted():
    m = load_engine()
    h1 = make_handler(m, headers={"Authorization": "Bearer secret-token"})
    assert h1._check_auth() is True, "Authorization: Bearer 应通过"
    h2 = make_handler(m, headers={"X-API-Token": "secret-token"})
    assert h2._check_auth() is True, "X-API-Token 应通过"


def test_missing_and_wrong_token_reasons():
    m = load_engine()
    h = make_handler(m)
    assert h._check_auth() is False and "缺少认证信息" in h._auth_reason, \
        "无凭据应说明缺认证信息，实际 %r" % (h._auth_reason,)
    h2 = make_handler(m, headers={"X-API-Token": "wrong"})
    assert h2._check_auth() is False and h2._auth_reason == "token 无效", \
        "错 token 应回「token 无效」，实际 %r" % (h2._auth_reason,)
    h3 = make_handler(m, token="")
    assert h3._check_auth() is False and "未配置" in h3._auth_reason, \
        "服务端无 token 应说明 API 已禁用，实际 %r" % (h3._auth_reason,)


def test_auth_failure_response_uses_reason():
    needle = 'self._respond(401, {"error": self._auth_reason})'
    assert SRC.count(needle) == 2, \
        "do_GET/do_POST 的 401 都应带具体原因，实际 %d 处" % SRC.count(needle)


# ══════════════════════════════════════════════════════════
# 第 6 条：/api/history 的 limit
# ══════════════════════════════════════════════════════════
def test_history_limit_parse_and_clamp():
    m = load_engine()
    cases = {
        "abc": None, "1.5": None, "-1": 1, "0": 1, "-5": 1,
        "1": 1, "50": 50, "1000": 1000, "5000": 1000,
        "": m.HISTORY_LIMIT_DEFAULT, None: m.HISTORY_LIMIT_DEFAULT,
    }
    for raw, expect in cases.items():
        got = m.parse_history_limit(raw)
        assert got == expect, "parse_history_limit(%r) 应得 %r，实际 %r" % (
            raw, expect, got)


def test_history_invalid_limit_returns_400():
    m = load_engine()
    db = StubDB()
    h = make_handler(m, path="/api/history?limit=abc")
    h.engine = StubEngine(db)
    h._handle_history()
    assert h.responses and h.responses[0][0] == 400, \
        "非法 limit 应回 400，实际 %r" % (h.responses,)
    assert "整数" in h.responses[0][1]["error"], "错误文案应说明原因"
    assert not db.calls, "400 时不应查库（旧版会整表导出）"


def test_history_valid_limit_clamped_in_query():
    m = load_engine()
    db = StubDB(rows=[], one=(0,))
    h = make_handler(m, path="/api/history?limit=5000&page=2")
    h.engine = StubEngine(db)
    h._handle_history()
    assert h.responses and h.responses[0][0] == 200, "合法 limit 应回 200"
    assert h.responses[0][1]["limit"] == 1000, "应夹到上限 1000"
    fetches = [c for c in db.calls if c[0] == "fetchall"]
    assert fetches, "应查询数据库"
    assert fetches[0][2] == (1000, 1000), \
        "LIMIT/OFFSET 应为参数绑定 (1000, 1000)，实际 %r" % (fetches[0][2],)


# ══════════════════════════════════════════════════════════
# 第 7 条：热重载更新 ban_mode + 切模式清旧规则
# ══════════════════════════════════════════════════════════
def test_apply_ban_config_updates_mode():
    m = load_engine()
    fw = m.Firewall("iptables", [], "drop")
    m.apply_ban_config(fw, {"method": "nftables", "mode": "rate_limit",
                            "whitelist": ["10.0.0.1"]})
    assert fw.method == "nftables", "method 应更新"
    assert fw.ban_mode == "rate_limit", "ban_mode 应更新（旧版 reload 漏掉）"
    assert "10.0.0.1" in fw.whitelist, "白名单应更新"
    assert "127.0.0.1" in fw.whitelist and "::1" in fw.whitelist, \
        "回环地址应始终在白名单"


def test_apply_ban_config_ignores_invalid_mode():
    m = load_engine()
    fw = m.Firewall("iptables", [], "reject")
    m.apply_ban_config(fw, {"mode": "bogus"})
    assert fw.ban_mode == "reject", "非法 mode 不应生效，实际 %r" % (
        fw.ban_mode,)


def test_purge_method_iptables_sweeps_only_own_rules():
    m = load_engine()
    fake = FakeSubprocess()
    fake.sweep_output = (
        "-A INPUT -s 1.2.3.4/32 -m hashlimit --hashlimit-name ps_abcd1234 "
        "-j ACCEPT\n"
        "-A INPUT -s 1.2.3.4/32 -j DROP\n"
        "-A INPUT -p tcp --dport 22 -j ACCEPT\n"
        "-A INPUT -p tcp --dport 80 -j ACCEPT\n")
    install_fake(m, fake)
    fw = m.Firewall("nftables", [], "drop")   # 当前已是新 method
    ok, details = fw.purge_method("iptables", ["1.2.3.4"])
    assert ok is True, "清理应成功，details=%r" % (details,)
    deletes = [c for c in fake.iptables_calls() if "-D" in c]
    joined = [" ".join(c) for c in deletes]
    assert any("ps_abcd1234" in x for x in joined), "应删掉本项目 hashlimit 规则"
    assert not any("--dport 22" in x for x in joined), "不能删用户自己的规则"
    assert not any("--dport 80" in x for x in joined), "不能删用户自己的规则"


def test_purge_method_nftables_deletes_table():
    m = load_engine()
    fake = FakeSubprocess()
    fake.table_exists = True
    install_fake(m, fake)
    fw = m.Firewall("iptables", [], "drop")   # 旧 method 是 nftables 之外的
    ok, details = fw.purge_method("nftables", [])
    assert ok is True, "应成功删除私有表，details=%r" % (details,)
    assert fake.argv_of("nft", "delete", "table"), "应执行 delete table"
    assert any("已删除 nft 私有表" in d for d in details), \
        "明细应说明删了什么，实际 %r" % (details,)


def test_switch_ban_plan_logs_and_rebans():
    m = load_engine()
    fake = FakeSubprocess()
    fake.sweep_output = ""
    install_fake(m, fake)
    engine = object.__new__(m.PortSentinel)
    engine.firewall = m.Firewall("nftables", [], "drop")
    engine.db = StubDB()
    engine.db.fetchall = lambda sql, params=(): [("1.1.1.1",), ("2.2.2.2",)]
    with capture_logs(m) as logs:
        engine._switch_ban_plan("iptables", "drop")
    joined = "\n".join(logs)
    assert "iptables/drop → nftables/drop" in joined, \
        "日志应写清 from→to，实际 %r" % (joined,)
    assert "重新下发封禁 2/2" in joined, "应报告重新封禁计数，实际 %r" % (joined,)
    rules = fake.argv_of("nft", "add", "rule")
    assert len(rules) == 2, "应给两个 IP 重新下发规则，实际 %d 条" % len(rules)


def test_reload_wires_switch_ban_plan():
    assert "old_mode = self.firewall.ban_mode" in SRC, \
        "reload 应记住旧 ban_mode"
    assert "self._switch_ban_plan(old_method, old_mode)" in SRC, \
        "reload 应在 method/mode 变化时调用切换流程"


# ══════════════════════════════════════════════════════════
TESTS = [
    # 第 1 条
    ("iptables_wrapper_injects_wait", test_iptables_wrapper_injects_wait),
    ("iptables_wrapper_respects_existing_wait",
     test_iptables_wrapper_respects_existing_wait),
    ("iptables_wait_configurable", test_iptables_wait_configurable),
    ("iptables_wrapper_warns_on_failure",
     test_iptables_wrapper_warns_on_failure),
    ("ban_all_calls_have_wait", test_ban_all_calls_have_wait),
    ("unban_all_calls_have_wait", test_unban_all_calls_have_wait),
    ("ban_fails_loudly_when_iptables_fails",
     test_ban_fails_loudly_when_iptables_fails),
    # 第 2 条
    ("nft_rebuilds_missing_chain", test_nft_rebuilds_missing_chain),
    ("nft_rebuilds_missing_table", test_nft_rebuilds_missing_table),
    ("nft_reports_when_rebuild_fails", test_nft_reports_when_rebuild_fails),
    ("nft_recheck_catches_silent_chain_loss",
     test_nft_recheck_catches_silent_chain_loss),
    ("ban_uses_checked_nft_and_reports", test_ban_uses_checked_nft_and_reports),
    # 第 3 条
    ("buffer_drop_counts_and_warns", test_buffer_drop_counts_and_warns),
    ("dropped_total_metric_exposed", test_dropped_total_metric_exposed),
    # 第 4 条
    ("connect_creates_missing_directory",
     test_connect_creates_missing_directory),
    ("connect_sets_busy_timeout", test_connect_sets_busy_timeout),
    ("connect_without_directory_part", test_connect_without_directory_part),
    # 第 5 条
    ("query_string_token_rejected", test_query_string_token_rejected),
    ("header_token_accepted", test_header_token_accepted),
    ("missing_and_wrong_token_reasons", test_missing_and_wrong_token_reasons),
    ("auth_failure_response_uses_reason",
     test_auth_failure_response_uses_reason),
    # 第 6 条
    ("history_limit_parse_and_clamp", test_history_limit_parse_and_clamp),
    ("history_invalid_limit_returns_400",
     test_history_invalid_limit_returns_400),
    ("history_valid_limit_clamped_in_query",
     test_history_valid_limit_clamped_in_query),
    # 第 7 条
    ("apply_ban_config_updates_mode", test_apply_ban_config_updates_mode),
    ("apply_ban_config_ignores_invalid_mode",
     test_apply_ban_config_ignores_invalid_mode),
    ("purge_method_iptables_sweeps_only_own_rules",
     test_purge_method_iptables_sweeps_only_own_rules),
    ("purge_method_nftables_deletes_table",
     test_purge_method_nftables_deletes_table),
    ("switch_ban_plan_logs_and_rebans", test_switch_ban_plan_logs_and_rebans),
    ("reload_wires_switch_ban_plan", test_reload_wires_switch_ban_plan),
]


def main():
    passed = failed = 0
    for name, fn in TESTS:
        try:
            fn()
        except AssertionError as e:
            failed += 1
            print("FAIL %s: %s" % (name, e))
        except Exception as e:
            failed += 1
            print("FAIL %s: %s: %s" % (name, type(e).__name__, e))
            traceback.print_exc()
        else:
            passed += 1
            print("PASS %s" % name)
    print("-" * 60)
    print("总计 %d 项：%d PASS / %d FAIL" % (len(TESTS), passed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
