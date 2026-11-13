# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import read_perf_stats  # noqa: E402

HEADER = ROOT / "app" / "src" / "perf_stats.h"


def test_reader_matches_the_firmware_layout():
    text = HEADER.read_text(encoding="utf-8")
    body = re.search(r"struct emacz_perf_stats \{(.*?)\n\};", text, re.S).group(1)
    fields = [(name, f"u{bits}") for bits, name in re.findall(r"uint(32|64)_t (\w+);", body)]
    assert fields == list(read_perf_stats.FIELDS)

    version = re.search(r"#define EMACZ_PERF_STATS_VERSION (\d+)u", text).group(1)
    assert int(version) == read_perf_stats.PERF_STATS_VERSION
