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
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"{patch.name}: {result.stderr}"


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
    ).stdout


def test_stacked_series_on_one_file(tmp_path, monkeypatch, capsys):
    repo = tmp_path / "zephyr"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@example.com")
    _git(repo, "config", "user.name", "t")
    target = repo / "drv.c"
    target.write_text("a\nb\nc\n", encoding="utf-8", newline="\n")
    _git(repo, "add", "drv.c")
    _git(repo, "commit", "-qm", "base")

    patch_dir = tmp_path / "patches"
    patch_dir.mkdir()
    for name, content in (("0001-x.patch", "a\nB\nc\n"), ("0002-y.patch", "a\nB\nC\n")):
        target.write_text(content, encoding="utf-8", newline="\n")
        (patch_dir / name).write_text(_git(repo, "diff"), encoding="utf-8", newline="\n")
        _git(repo, "add", "drv.c")
    _git(repo, "reset", "-q", "--hard", "HEAD")
    monkeypatch.setattr(apply_zephyr_patches, "PATCH_DIR", patch_dir)
    monkeypatch.setattr(apply_zephyr_patches, "ROOT", tmp_path)
    monkeypatch.setattr(sys, "argv", ["apply", "--zephyr-dir", str(repo)])
    patches = sorted(patch_dir.glob("*.patch"))

    assert apply_zephyr_patches.series_state(repo, patches) == 0
    assert apply_zephyr_patches.main() == 0
    assert target.read_text(encoding="utf-8") == "a\nB\nC\n"
    assert apply_zephyr_patches.series_state(repo, patches) == 2
    assert apply_zephyr_patches.main() == 0
    assert "already applied" in capsys.readouterr().out

    target.write_text("a\nB\nc\n", encoding="utf-8", newline="\n")
    assert apply_zephyr_patches.series_state(repo, patches) == 1
    assert apply_zephyr_patches.main() == 0
    assert target.read_text(encoding="utf-8") == "a\nB\nC\n"

    target.write_text("a\nlocal edit\nC\n", encoding="utf-8", newline="\n")
    assert apply_zephyr_patches.series_state(repo, patches) is None
    assert apply_zephyr_patches.main() == 1
