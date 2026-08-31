# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

from __future__ import annotations

import importlib.util
import ipaddress
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("emacz_config", ROOT / "scripts" / "emacz_config.py")
assert SPEC is not None and SPEC.loader is not None
emacz_config = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = emacz_config
SPEC.loader.exec_module(emacz_config)


def sample_message():
    return emacz_config.Message(
        op=emacz_config.CONFIG,
        status=0,
        prefix=24,
        xid=0x12345678,
        mac=bytes.fromhex("020000000001"),
        ip=ipaddress.IPv4Address("192.168.44.20"),
        gateway=ipaddress.IPv4Address("192.168.44.1"),
        token=0x89ABCDEF,
    )


def test_protocol_round_trip():
    message = sample_message()
    encoded = emacz_config.encode_message(message)
    assert len(encoded) == 36
    assert emacz_config.decode_message(encoded) == message


def test_protocol_rejects_corrupt_crc():
    encoded = bytearray(emacz_config.encode_message(sample_message()))
    encoded[20] ^= 1
    with pytest.raises(ValueError, match="CRC"):
        emacz_config.decode_message(bytes(encoded))


@pytest.mark.parametrize(
    "ip,prefix,gateway",
    [
        ("192.168.1.0", 24, "0.0.0.0"),
        ("192.168.1.255", 24, "0.0.0.0"),
        ("224.0.0.1", 24, "0.0.0.0"),
        ("192.168.1.20", 0, "0.0.0.0"),
        ("192.168.1.20", 24, "192.168.2.1"),
    ],
)
def test_rejects_invalid_config(ip, prefix, gateway):
    with pytest.raises(ValueError):
        emacz_config.validate_config(
            ipaddress.IPv4Address(ip), prefix, ipaddress.IPv4Address(gateway)
        )


def test_accepts_no_gateway_and_subnet_gateway():
    emacz_config.validate_config(
        ipaddress.IPv4Address("10.20.30.40"), 24, ipaddress.IPv4Address("0.0.0.0")
    )
    emacz_config.validate_config(
        ipaddress.IPv4Address("10.20.30.40"), 24, ipaddress.IPv4Address("10.20.30.1")
    )
