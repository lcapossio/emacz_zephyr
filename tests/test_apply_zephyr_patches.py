# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Leonardo Capossio - bard0 design

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "apply_zephyr_patches", ROOT / "scripts" / "apply_zephyr_patches.py"
)
assert SPEC is not None and SPEC.loader is not None
apply_zephyr_patches = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = apply_zephyr_patches
SPEC.loader.exec_module(apply_zephyr_patches)


def test_explicit_zephyr_dir_does_not_require_west(tmp_path, monkeypatch):
    zephyr_dir = tmp_path / "zephyr"
    zephyr_dir.mkdir()
    monkeypatch.setattr(
        apply_zephyr_patches,
        "west_zephyr_dir",
        lambda: (_ for _ in ()).throw(AssertionError("west should not run")),
    )

    assert apply_zephyr_patches.find_zephyr_dir(zephyr_dir) == zephyr_dir.resolve()


def test_zephyr_base_precedes_west(tmp_path, monkeypatch):
    zephyr_dir = tmp_path / "zephyr"
    zephyr_dir.mkdir()
    monkeypatch.setenv("ZEPHYR_BASE", str(zephyr_dir))
    monkeypatch.setattr(
        apply_zephyr_patches,
        "west_zephyr_dir",
        lambda: (_ for _ in ()).throw(AssertionError("west should not run")),
    )

    assert apply_zephyr_patches.find_zephyr_dir() == zephyr_dir.resolve()


def test_west_project_path_is_used(tmp_path, monkeypatch):
    zephyr_dir = tmp_path / "workspace" / "deps" / "zephyr"
    zephyr_dir.mkdir(parents=True)
    monkeypatch.delenv("ZEPHYR_BASE", raising=False)
    monkeypatch.setattr(
        apply_zephyr_patches,
        "west_zephyr_dir",
        lambda: zephyr_dir.resolve(),
    )

    assert apply_zephyr_patches.find_zephyr_dir() == zephyr_dir.resolve()


def test_all_zephyr_patches_have_valid_git_syntax():
    patches = sorted((ROOT / "patches" / "zephyr").glob("*.patch"))
    assert patches

    for patch in patches:
        result = subprocess.run(
            ["git", "apply", "--numstat", str(patch)],
            cwd=ROOT,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert result.returncode == 0, f"{patch.name}: {result.stderr}"
