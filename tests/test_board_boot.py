# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

from __future__ import annotations

import argparse
import importlib.util
import io
import os
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


import fcapz_jtag

r5 = load("load_zynqmp_r5")
suite = load("run_board_suite")


def r5_script(url: str | None = None) -> str:
    return r5.xsdb_script(Path("shell.bit"), Path("fsbl.elf"), Path("zephyr.elf"),
                          "xczu7", url)


def test_r5_script_fills_every_field():
    script = r5_script()
    assert not re.search(r"@[A-Z_]+@", script)
    assert "set cable [board_cable xczu7]" in script
    assert "mwr 0xff5e0200 0x100" in script
    assert "\n    connect\n" in script


def test_r5_script_connects_to_a_remote_hw_server():
    assert "connect -url tcp:lab:3121" in r5_script("tcp:lab:3121")


def test_r5_script_selects_every_target_on_the_board_cable():
    script = r5_script()
    steps = script[script.index("step connect"):]
    # Every target switch goes through the cable-pinned select, the FPGA
    # one included, before anything is written or reset
    assert "targets -set" not in steps
    order = [steps.index(f"select {name}") for name in ("PSU", "{PS TAP}", "*R5*#0")]
    assert order == sorted(order)
    assert steps.index("select PSU") < steps.index("rst -system")


def test_r5_script_runs_the_fsbl_after_the_bitstream_and_before_zephyr():
    script = r5_script()
    fpga, fsbl, zephyr = (script.index(f"step {name}") for name in ("fpga", "fsbl", "r5-load"))
    assert fpga < fsbl < zephyr
    # the done flag is cleared before the FSBL starts, then polled
    body = script[fsbl:zephyr]
    assert body.index("& ~0x1") < body.index("dow {") < body.index("while {")


def test_ps_script_without_an_image_stops_after_the_fsbl():
    script = r5.xsdb_script(Path("vex.bit"), Path("fsbl.elf"), None, "xczu7", None)
    assert not re.search(r"@[A-Z_]+@", script)
    assert "step fsbl" in script
    assert "step r5-load" not in script and "step r5-run" not in script
    assert script.index("step fsbl") < script.index("LOAD_DONE")


def suite_args(**values) -> argparse.Namespace:
    defaults = {"shell": "vex", "bit": None, "image": None, "load_addr": None}
    defaults.update(values)
    return argparse.Namespace(**defaults)


def test_suite_loads_soft_cpu_shells_into_ram():
    command = suite.load_command(suite_args(image=Path("z.bin")), suite.SHELLS["vex"])
    assert Path(command[1]).name == "load_zephyr_bram.py"
    assert command[2:] == ["--shell", "vex", "--file", "z.bin"]


def test_suite_loads_an_image_linked_above_the_dcache_window():
    command = suite.load_command(suite_args(load_addr=0x98000000), suite.SHELLS["vex"])
    assert command[-2:] == ["--addr", "0x98000000"]


def test_bram_loader_jump_stub_is_lui_jalr():
    bram = load("load_zephyr_bram")
    # GNU as: lui t0,0x98000 / jr t0
    assert bram.jump_stub(0x98000000) == [0x980002B7, 0x00028067]
    with pytest.raises(ValueError):
        bram.jump_stub(0x98000004)


def test_suite_boots_the_r5_shell_through_the_ps():
    shell = suite.SHELLS["zcu106_r5"]
    command = suite.load_command(
        suite_args(shell="zcu106_r5", bit=Path("r5.bit"), image=Path("zephyr.elf")), shell)
    assert Path(command[1]).name == "load_zynqmp_r5.py"
    assert command[2:] == ["--tap", "xczu7", "--bit", "r5.bit", "--elf", "zephyr.elf"]
    assert shell.ps_boot and not suite.SHELLS["zcu106_vex"].ps_boot
    assert suite.program_command(suite_args(shell="zcu106_r5"), shell) is None


def test_suite_programs_the_zcu106_vex_shell_through_the_ps():
    shell = suite.SHELLS["zcu106_vex"]
    args = suite_args(shell="zcu106_vex", bit=Path("vex.bit"), image=Path("z.bin"))
    program = suite.program_command(args, shell)
    assert Path(program[1]).name == "load_zynqmp_r5.py"
    assert program[2:] == ["--shell", "zcu106_vex", "--tap", "xczu7", "--bit", "vex.bit"]
    load = suite.load_command(args, shell)
    assert Path(load[1]).name == "load_zephyr_bram.py"
    assert load[2:] == ["--shell", "zcu106_vex", "--file", "z.bin"]


def test_suite_programs_the_arty_shells_with_vivado():
    program = suite.program_command(suite_args(shell="mbv"), suite.SHELLS["mbv"])
    assert Path(program[1]).name == "program_fpga.py"
    assert program[2:] == ["--shell", "mbv"]


def test_bursts_never_cross_a_4k_page():
    addr = 0x90000FC0
    spans = list(fcapz_jtag.bursts(addr, 64, 15))
    assert sum(count for _, count in spans) == 64
    offset = 0
    for start, count in spans:
        assert start == offset and 1 <= count <= 15
        first = addr + start * 4
        assert first // 0x1000 == (first + count * 4 - 1) // 0x1000
        offset += count
    # the burst before the page boundary is cut short to end on it
    assert spans[:2] == [(0, 15), (15, 1)]


def test_bursts_reject_unaligned_addresses():
    with pytest.raises(ValueError):
        list(fcapz_jtag.bursts(0x90000002, 4, 15))


def flaky(failures: list[str]):
    """A session that raises each of `failures` in turn, then returns its call count."""
    calls = []

    def session():
        calls.append(None)
        if len(calls) <= len(failures):
            raise RuntimeError(f"xsdb: {failures[len(calls) - 1]}")
        return len(calls)

    return session


def test_open_session_reruns_through_transient_xsdb_errors(monkeypatch):
    monkeypatch.setattr(fcapz_jtag.time, "sleep", lambda _s: None)
    session = flaky(["target list is empty", "JTAG node is not accessible"])
    assert fcapz_jtag.open_session(session) == 3


def test_open_session_gives_up_after_its_tries(monkeypatch):
    monkeypatch.setattr(fcapz_jtag.time, "sleep", lambda _s: None)
    session = flaky(["JTAG node is not accessible"] * fcapz_jtag.XSDB_TRIES)
    with pytest.raises(RuntimeError, match="not accessible"):
        fcapz_jtag.open_session(session)


def test_open_session_does_not_rerun_other_errors(monkeypatch):
    monkeypatch.setattr(fcapz_jtag.time, "sleep", lambda _s: None)
    session = flaky(["expected 4 raw scan results, got 3", "target list is empty"])
    with pytest.raises(RuntimeError, match="got 3"):
        fcapz_jtag.open_session(session)


class FakeBridge:
    def __init__(self, fail: bool):
        self.fail = fail
        self.closed = False

    def axi_read(self, _addr: int) -> int:
        if self.fail:
            raise RuntimeError("xsdb: JTAG node is not accessible")
        return 7

    def close(self) -> None:
        self.closed = True


def test_read_reruns_the_whole_session_after_a_failed_scan(monkeypatch):
    monkeypatch.setattr(fcapz_jtag.time, "sleep", lambda _s: None)
    bridges = [FakeBridge(fail=True), FakeBridge(fail=False)]
    opened = iter(bridges)
    monkeypatch.setattr(fcapz_jtag, "_connect_axi", lambda _tap, _chain: next(opened))
    assert fcapz_jtag.read("xczu7", 4, lambda axi: axi.axi_read(0x0)) == 7
    assert all(bridge.closed for bridge in bridges)


def bidi_args(**values) -> argparse.Namespace:
    defaults = {"board_ip": "192.168.237.201", "bind": "192.168.237.1", "tx_rate_mbps": 0.0,
                "tx_duration": 5.0, "bidi_rx_mbps": None}
    defaults.update(values)
    return argparse.Namespace(**defaults)


def option(command: list[str], name: str) -> str:
    return command[command.index(name) + 1]


def test_bidi_rx_load_is_timed_over_stdin():
    shell = suite.SHELLS["zcu106_r5"]
    rx = suite.bidi_rx_command(bidi_args(), shell, 957.1)
    assert Path(rx[1]).name == "run_udp_accounting.py"
    assert "--stdin-control" in rx
    assert float(option(rx, "--rate-mbps")) == 957.1
    assert float(option(rx, "--duration")) == suite.BIDI_RX_CAP_S
    assert option(rx, "--addr") == hex(shell.perf_stats)


def test_line_rate_is_the_links_payload_rate():
    # 1472 B of payload per 1538 B on the wire
    assert suite.line_rate_mbps(suite.SHELLS["vex"]) == 95.7
    assert suite.line_rate_mbps(suite.SHELLS["zcu106_r5"]) == 957.1


# Stand-ins for the two scripts. The RX one follows --stdin-control and logs
# what it was told; the TX one prints its window markers.
FAKE_RX = """
import sys
print('sending_s=120', flush=True)
for _ in range(2):
    line = sys.stdin.readline()
    print('got=' + (line.strip() or 'eof'), flush=True)
print('stopped_by=' + ('stdin' if line else 'duration'))
sys.stdin.read()
print('final_read')
"""
FAKE_RX_CAPPED = FAKE_RX.replace("('stdin' if line else 'duration')", "'duration'")
FAKE_TX = "print('tx_command_sent', flush=True); print('tx_reply_received'); " \
          "print('board_payload_mbps=7.5')"
FAKE_TX_NO_START = "print('control_check=fail'); raise SystemExit(2)"


def fake_bidi(monkeypatch, rx_code: str, tx_code: str):
    monkeypatch.setattr(suite, "bidi_rx_command",
                        lambda _a, _s, _r: [sys.executable, "-c", rx_code])
    monkeypatch.setattr(suite, "tx_command", lambda _a, _s: [sys.executable, "-c", tx_code])
    return suite.run_bidi(bidi_args(), suite.SHELLS["vex"], 95.7)


def test_bidi_runs_the_rx_load_over_the_tx_window(monkeypatch):
    result = fake_bidi(monkeypatch, FAKE_RX, FAKE_TX)
    assert result.error is None and result.rx_ok and result.tx_ok
    assert "board_payload_mbps=7.5" in result.tx_log
    told = [line for line in result.rx_log if line.startswith(("got=", "final_read"))]
    assert told == ["got=go", "got=stop", "final_read"]


def test_bidi_rejects_an_rx_load_that_hit_its_cap(monkeypatch):
    result = fake_bidi(monkeypatch, FAKE_RX_CAPPED, FAKE_TX)
    assert result.error is not None


def test_bidi_without_a_tx_start_ends_the_rx_script(monkeypatch):
    result = fake_bidi(monkeypatch, FAKE_RX, FAKE_TX_NO_START)
    assert result.error is not None and not result.tx_ok
    assert "got=eof" in result.rx_log and "final_read" in result.rx_log


@pytest.mark.parametrize("text", ["go\nstop\n", "go\n", ""])
def test_stdin_control_releases_every_step_by_eof(monkeypatch, text):
    udp = load("run_udp_accounting")
    monkeypatch.setattr(udp.sys, "stdin", io.StringIO(text))
    control = udp.StdinControl()
    assert control.eof.wait(5.0)
    assert control.go.is_set() and control.stop.is_set()


def test_stdin_control_waits_for_the_stop_line(monkeypatch):
    udp = load("run_udp_accounting")
    reader, writer = os.pipe()
    monkeypatch.setattr(udp.sys, "stdin", os.fdopen(reader, "r"))
    with os.fdopen(writer, "w") as feed:
        control = udp.StdinControl()
        feed.write("go\n")
        feed.flush()
        assert control.go.wait(5.0)
        assert not control.stop.wait(0.2)
        feed.write("stop\n")
        feed.flush()
        assert control.stop.wait(5.0)
        assert not control.eof.is_set()
    assert control.eof.wait(5.0)


def test_udp_sender_stops_on_request():
    udp = load("run_udp_accounting")
    stop = udp.threading.Event()
    stop.set()
    args = argparse.Namespace(rate_mbps=1.0, packet_size=64, target="127.0.0.1", port=9,
                              bind="127.0.0.1", timeout=1.0, duration=60.0)
    assert udp.send_fast_sink(args, stop) == 0


def test_bidi_rx_rate_is_the_shells_unless_given():
    shell = suite.SHELLS["zcu106_vex"]
    assert suite.bidi_rx_mbps(bidi_args(), shell) == shell.bidi_rx_mbps
    assert suite.bidi_rx_mbps(bidi_args(bidi_rx_mbps=1.5), shell) == 1.5
