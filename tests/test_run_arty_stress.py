# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

from __future__ import annotations

import importlib.util
import ipaddress
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("run_arty_stress", SCRIPTS / "run_arty_stress.py")
assert SPEC is not None and SPEC.loader is not None
stress = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = stress
SPEC.loader.exec_module(stress)


def snapshot(**updates: int) -> dict[str, int | str]:
    values: dict[str, int | str] = {
        "magic": "EZRX",
        "uptime": 1000,
        "sink_p": 100,
        "sink_b": 147200,
        "mac_rx": 110,
        "dma": 110,
    }
    values.update({name: 0 for name in stress.ERROR_COUNTERS})
    values.update(updates)
    return values


def encode(values: dict[str, int | str]) -> bytes:
    return (" ".join(f"{name}={value}" for name, value in values.items()) + "\r\n").encode()


def test_parse_acceptance_snapshot():
    assert stress.parse_snapshot(encode(snapshot())) == snapshot()


def test_parse_snapshot_rejects_wrong_identity_and_missing_fields():
    with pytest.raises(ValueError, match="EZRX"):
        stress.parse_snapshot(b"magic=OTHER uptime=1\n")
    with pytest.raises(ValueError, match="missing"):
        stress.parse_snapshot(b"magic=EZRX uptime=1\n")


def test_evaluate_accepts_exact_delivery_and_zero_errors():
    before = snapshot()
    after = snapshot(uptime=601000, sink_p=1100, sink_b=1619200, mac_rx=1110, dma=1110)
    result = stress.evaluate(before, after, 1000, 1472000, 600.0, 100.0)
    assert result.sink_packets == 1000
    assert result.sink_bytes == 1472000
    assert result.delivery_pct == 100.0


def test_evaluate_rejects_loss_and_error_counter_changes():
    before = snapshot()
    lost = snapshot(uptime=2000, sink_p=1099, sink_b=1617728)
    with pytest.raises(RuntimeError, match="delivery"):
        stress.evaluate(before, lost, 1000, 1472000, 1.0, 100.0)

    failed = snapshot(uptime=2000, sink_p=1100, sink_b=1619200, dma_err=1)
    with pytest.raises(RuntimeError, match="dma_err"):
        stress.evaluate(before, failed, 1000, 1472000, 1.0, 100.0)


def test_choose_bind_ip_is_interface_name_agnostic(monkeypatch):
    monkeypatch.setattr(
        stress.config,
        "active_ipv4",
        lambda interface, bind: [("enp3s0", "10.20.30.1"), ("Wi-Fi", "192.168.1.5")],
    )
    selected = stress.choose_bind_ip(ipaddress.IPv4Address("10.20.30.40"), 24, None, None)
    assert selected == "10.20.30.1"
