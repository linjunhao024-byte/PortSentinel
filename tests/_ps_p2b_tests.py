#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""t27 离线测试：PortSentinel 六条部署/清理 P2。

不跑 docker、不执行 iptables/nft、不监听端口；sqlite 全用临时库，
shell 测试用临时脚本副本 + 假 sqlite3。
"""
import io
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import types
import unittest

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
ENGINE = os.path.join(BASE, "port-monitor")
SHELL = os.path.join(BASE, "port-monitor.sh")
SRC = io.open(ENGINE, encoding="utf-8", newline="").read()
SHELL_SRC = io.open(SHELL, encoding="utf-8", newline="").read()


def load_engine():
    mod = types.ModuleType("port_monitor_p2b")
    mod.__file__ = ENGINE
    exec(compile(SRC, ENGINE, "exec"), mod.__dict__)
    return mod


def make_shell_copy(tmp):
    """复制 shell 脚本，去掉非 Linux 依赖检查与 main，便于 source 测试。"""
    text = SHELL_SRC
    text = text.replace(
        'if [[ "${1:-}" != "--version" && "${1:-}" != "-v" ]]; then\n    _check_deps\nfi',
        '# deps check disabled by test')
    text = text.replace('\nmain "$@"\n', '\n: # main disabled by test\n')
    path = os.path.join(tmp, "pm.sh")
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    return path


def run_bash(script, env=None, cwd=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run(
        ["bash", script], capture_output=True, text=True,
        encoding="utf-8", errors="replace", env=e, cwd=cwd, timeout=30)


class DeploymentFilesTests(unittest.TestCase):
    def test_dockerfile_non_root_and_dirs(self):
        text = io.open(os.path.join(BASE, "Dockerfile"), encoding="utf-8").read()
        self.assertIn("adduser -u 10001", text)
        self.assertIn("chown -R portsentinel:portsentinel", text)
        self.assertIn("USER portsentinel", text)
        self.assertNotIn("USER root", text)

    def test_compose_hardening_and_healthcheck(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML 不可用")
        d = yaml.safe_load(io.open(os.path.join(BASE, "docker-compose.yml"), encoding="utf-8"))
        svc = d["services"]["port-sentinel"]
        self.assertEqual(svc["user"], "10001:10001")
        self.assertIs(svc["read_only"], True)
        self.assertIn("ALL", svc["cap_drop"])
        self.assertEqual(set(svc["cap_add"]), {"NET_ADMIN", "NET_RAW"})
        self.assertEqual(svc["network_mode"], "host")
        self.assertIn("no-new-privileges:true", svc["security_opt"])
        self.assertIn("/tmp", "\n".join(svc["tmpfs"]))
        hc = svc["healthcheck"]
        cmd = " ".join(hc["test"])
        self.assertIn("/api/health", cmd)
        self.assertIn("PORTSENTINEL_API_PORT", cmd)
        self.assertNotIn("/proc", cmd)
        self.assertIn("start_period", hc)
        self.assertGreaterEqual(hc["retries"], 3)


class StartupRestoreTests(unittest.TestCase):
    def setUp(self):
        self.m = load_engine()
        self.tmp = tempfile.mkdtemp()
        self.db = self.m.Database(os.path.join(self.tmp, "t.db"))
        self.engine = object.__new__(self.m.PortSentinel)
        self.engine.db = self.db
        self.engine._PENDING_BAN_TIMEOUT = 300
        self.fw = types.SimpleNamespace(
            calls=[], ban_ok=True, unban_ok=True,
            ban=lambda ip: (self.fw.calls.append(("ban", ip)) or self.fw.ban_ok),
            unban=lambda ip: (self.fw.calls.append(("unban", ip)) or self.fw.unban_ok),
        )
        self.engine.firewall = self.fw

    def tearDown(self):
        try:
            self.db.conn.close()
        except Exception:
            pass
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _insert(self, ip, status, blocked_at, unblock_at, permanent=0):
        self.db.conn.execute(
            "INSERT INTO blocked_ips(ip,attack_type,blocked_at,unblock_at,permanent,status) "
            "VALUES(?,?,?,?,?,?)",
            (ip, "test", blocked_at, unblock_at, permanent, status))
        self.db.conn.commit()
        self.db._load_blocked_cache()

    def test_expired_active_removed_and_future_reapplied(self):
        now = time.time()
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
        self._insert("1.1.1.1", "active", fmt(now - 100), fmt(now - 10))
        self._insert("2.2.2.2", "active", fmt(now - 100), fmt(now + 1000))
        with self.assertLogs(self.m.logger, level="INFO") as cm:
            self.m.PortSentinel._restore_bans(self.engine)
        ips = [r[0] for r in self.db.fetchall("SELECT ip FROM blocked_ips")]
        self.assertEqual(ips, ["2.2.2.2"])
        self.assertIn(("unban", "1.1.1.1"), self.fw.calls)
        self.assertIn(("ban", "2.2.2.2"), self.fw.calls)
        self.assertTrue(any("启动恢复" in line for line in cm.output))

    def test_pending_stale_cleaned_recent_retried_and_failed_rolled_back(self):
        now = time.time()
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
        self._insert("3.3.3.3", "pending", fmt(now - 400), fmt(now + 1000))
        self._insert("4.4.4.4", "pending", fmt(now - 10), fmt(now + 1000))
        self._insert("5.5.5.5", "pending", fmt(now - 10), fmt(now + 1000))
        # 4.4.4.4 成功，5.5.5.5 失败
        self.fw.ban = lambda ip: (self.fw.calls.append(("ban", ip)) or ip != "5.5.5.5")
        self.m.PortSentinel._restore_bans(self.engine)
        rows = dict(self.db.fetchall("SELECT ip,status FROM blocked_ips"))
        self.assertNotIn("3.3.3.3", rows)
        self.assertEqual(rows.get("4.4.4.4"), "active")
        self.assertNotIn("5.5.5.5", rows)
        self.assertIn(("ban", "4.4.4.4"), self.fw.calls)
        self.assertIn(("ban", "5.5.5.5"), self.fw.calls)

    def test_get_expired_bans_ignores_pending(self):
        now = time.time()
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
        self._insert("6.6.6.6", "pending", fmt(now - 100), fmt(now - 10))
        self._insert("7.7.7.7", "active", fmt(now - 100), fmt(now - 10))
        self.assertEqual(self.db.get_expired_bans(), ["7.7.7.7"])

    def test_pending_stale_unban_failure_keeps_record(self):
        now = time.time()
        fmt = lambda t: time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))
        self._insert("8.8.8.8", "pending", fmt(now - 400), fmt(now + 1000))
        self.fw.unban_ok = False
        with self.assertLogs(self.m.logger, level="ERROR") as cm:
            self.m.PortSentinel._restore_bans(self.engine)
        self.assertIsNotNone(self.db.fetchone(
            "SELECT ip FROM blocked_ips WHERE ip=?", ("8.8.8.8",)))
        self.assertIn(("unban", "8.8.8.8"), self.fw.calls)
        self.assertTrue(any("旧规则未能撤销" in line for line in cm.output))


class BanOrderTests(unittest.TestCase):
    def setUp(self):
        self.m = load_engine()
        self.tmp = tempfile.mkdtemp()
        self.db = self.m.Database(os.path.join(self.tmp, "t.db"))
        self.engine = object.__new__(self.m.PortSentinel)
        self.engine.db = self.db
        self.engine.firewall = types.SimpleNamespace(
            ban_ok=True, calls=[], is_whitelisted=lambda ip: False)
        self.engine.firewall.ban = lambda ip: (self.engine.firewall.calls.append(ip) or self.engine.firewall.ban_ok)
        self.engine.attack_correlator = types.SimpleNamespace(record=lambda *a, **k: {})
        self.engine.response_manager = types.SimpleNamespace(trigger=lambda *a, **k: None)
        self.engine.threat_intel = types.SimpleNamespace(check=lambda ip: {})
        self.engine._format_duration = lambda sec: f"{sec}s"
        self.engine._render_template = lambda *a, **k: ""
        self.engine.port_mapper = types.SimpleNamespace(get_service=lambda p: "svc")
        self.engine.alerter = types.SimpleNamespace(enqueue=lambda m: None)
        self.engine._templates = {}
        self.engine._alert_cooldown = lambda *a, **k: None

    def tearDown(self):
        try:
            self.db.conn.close()
        except Exception:
            pass
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_success_writes_pending_then_active(self):
        self.m.PortSentinel._execute_ban(self.engine, "8.8.8.8", "scan", 80, 60)
        row = self.db.fetchone("SELECT status FROM blocked_ips WHERE ip=?", ("8.8.8.8",))
        self.assertEqual(row[0], "active")
        self.assertIn("8.8.8.8", self.engine.firewall.calls)

    def test_firewall_failure_rolls_back_db(self):
        self.engine.firewall.ban_ok = False
        with self.assertLogs(self.m.logger, level="ERROR") as cm:
            self.m.PortSentinel._execute_ban(self.engine, "9.9.9.9", "scan", 80, 60)
        self.assertIsNone(self.db.fetchone(
            "SELECT status FROM blocked_ips WHERE ip=?", ("9.9.9.9",)))
        self.assertTrue(any("回滚" in line for line in cm.output))

    def test_api_ban_failure_rolls_back(self):
        self.engine.firewall.ban_ok = False
        handler = object.__new__(self.m.APIHandler)
        handler.engine = self.engine
        out = {}
        handler._respond = lambda code, data: out.update(code=code, data=data)
        handler._handle_ban({"ip": "10.10.10.10", "duration": "1h"})
        self.assertEqual(out.get("code"), 500)
        self.assertIsNone(self.db.fetchone(
            "SELECT status FROM blocked_ips WHERE ip=?", ("10.10.10.10",)))


class ShellWhitelistTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.script = make_shell_copy(self.tmp)
        self.cfg = os.path.join(self.tmp, "config.yaml")
        io.open(self.cfg, "w", encoding="utf-8", newline="").write(
            'ban:\n  enabled: true\n  whitelist:\n    - "10.0.0.1"\n\nother:\n  x: 1\n')

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _add(self, entry):
        runner = os.path.join(self.tmp, "run.sh")
        io.open(runner, "w", encoding="utf-8", newline="").write(
            'source "%s"\nCONFIG_FILE="%s"\n_add_whitelist_entry "%s"\n'
            % (self.script, self.cfg, entry))
        return run_bash(runner)

    def test_add_inserts_markers_and_entry(self):
        r = self._add("10.0.0.2")
        self.assertEqual(r.returncode, 0, r.stderr)
        text = io.open(self.cfg, encoding="utf-8").read()
        self.assertIn("# >>> whitelist >>>", text)
        self.assertIn("# <<< whitelist <<<", text)
        self.assertIn('    - "10.0.0.2"', text)
        self.assertLess(text.index("# >>> whitelist >>>"), text.index('    - "10.0.0.2"'))
        self.assertLess(text.index('    - "10.0.0.2"'), text.index("# <<< whitelist <<<"))
        self.assertLess(text.index("# <<< whitelist <<<"), text.index("other:"))
        self.assertEqual(text.count("# >>> whitelist >>>"), 1)

    def test_second_add_no_duplicate(self):
        self._add("10.0.0.2")
        r = self._add("10.0.0.2")
        self.assertEqual(r.returncode, 0)
        text = io.open(self.cfg, encoding="utf-8").read()
        self.assertEqual(text.count('    - "10.0.0.2"'), 1)
        self.assertEqual(text.count("# >>> whitelist >>>"), 1)

    def test_missing_whitelist_fails_and_restores(self):
        before = 'ban:\n  enabled: true\n\nother:\n  x: 1\n'
        io.open(self.cfg, "w", encoding="utf-8", newline="").write(before)
        r = self._add("10.0.0.9")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(io.open(self.cfg, encoding="utf-8").read(), before)


class ShellCleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.script = make_shell_copy(self.tmp)
        self.bindir = os.path.join(self.tmp, "bin")
        self.data = os.path.join(self.tmp, "data")
        self.logs = os.path.join(self.tmp, "logs")
        os.makedirs(self.bindir)
        os.makedirs(self.data)
        os.makedirs(self.logs)
        io.open(os.path.join(self.data, "monitor.db"), "w").close()
        fake = os.path.join(self.bindir, "sqlite3")
        io.open(fake, "w", encoding="utf-8", newline="").write(
            '#!/bin/sh\necho "$@" >> "$SQLITE_LOG"\n'
            'case "$*" in\n'
            '  *"COUNT(*)"*) echo 2; exit "${PREVIEW_RC:-0}" ;;\n'
            '  *DELETE*) exit "${DELETE_RC:-0}" ;;\n'
            '  *VACUUM*) exit "${VACUUM_RC:-0}" ;;\n'
            '  *) exit 0 ;;\n'
            'esac\n')
        os.chmod(fake, os.stat(fake).st_mode | stat.S_IEXEC)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _run(self, extra_env=None):
        runner = os.path.join(self.tmp, "run_cleanup.sh")
        io.open(runner, "w", encoding="utf-8", newline="").write(
            'source "%s"\n'
            'DATA_DIR="%s"\nLOG_DIR="%s"\nCONFIG_FILE="%s/config.yaml"\n'
            'check_root(){ :; }\nprint_banner(){ :; }\nask(){ echo 30; }\n'
            'ask_yn(){ echo y; }\ndo_cleanup\n'
            % (self.script, self.data, self.logs, self.tmp))
        env = {"PATH": self.bindir + os.pathsep + os.environ.get("PATH", ""),
               "SQLITE_LOG": os.path.join(self.tmp, "sql.log")}
        env.update(extra_env or {})
        return run_bash(runner, env=env)

    def test_success_checks_rc_and_reports(self):
        r = self._run()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("已清理 2 项", r.stderr)
        log = io.open(os.path.join(self.tmp, "sql.log"), encoding="utf-8").read()
        self.assertIn("DELETE FROM attacks", log)
        self.assertIn("VACUUM", log)

    def test_delete_failure_returns_nonzero(self):
        r = self._run({"DELETE_RC": "1"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("数据库删除失败", r.stderr)
        self.assertIn("失败 1 项", r.stderr)

    def test_preview_failure_is_not_success(self):
        r = self._run({"PREVIEW_RC": "1"})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("数据库预览失败", r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
