# SPDX-License-Identifier: Apache-2.0
"""TDD tests for the deepspan-codegen CLI."""

import subprocess
import sys
from pathlib import Path

import pytest
from typer.testing import CliRunner

from deepspan_codegen.cli import app
from tests.conftest import FULL_YAML, MINIMAL_YAML

runner = CliRunner()


# ── CLI via typer.testing.CliRunner ──────────────────────────────────────────

class TestCLI:
    def test_generate_all_targets(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(FULL_YAML)
        out_dir = tmp_path / "gen"

        result = runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--target", "all",
        ])
        assert result.exit_code == 0, result.output
        assert "Done." in result.output

    def test_generate_creates_six_files(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(FULL_YAML)
        out_dir = tmp_path / "gen"

        runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
        ])
        files = list(out_dir.rglob("*"))
        non_dirs = [f for f in files if f.is_file()]
        assert len(non_dirs) == 6

    def test_generate_single_target_kernel(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)
        out_dir = tmp_path / "gen"

        runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--target", "kernel",
        ])
        files = list(out_dir.rglob("*.h"))
        assert len(files) == 1
        assert "dispatch" not in files[0].name  # firmware dispatch excluded

    def test_generate_single_target_go(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)
        out_dir = tmp_path / "gen"

        runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--target", "go",
        ])
        go_files = list(out_dir.rglob("*.go"))
        assert len(go_files) == 1

    def test_generate_comma_targets(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)
        out_dir = tmp_path / "gen"

        runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--target", "kernel,go",
        ])
        files = list(out_dir.rglob("*"))
        non_dirs = [f for f in files if f.is_file()]
        assert len(non_dirs) == 2

    def test_generate_invalid_target_exits_nonzero(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)

        result = runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--target", "invalid_target",
        ])
        assert result.exit_code != 0

    def test_dry_run_no_files_created(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)
        out_dir = tmp_path / "gen"

        result = runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--dry-run",
        ])
        assert result.exit_code == 0
        assert "would write" in result.output
        # No actual output files are written (directory may exist from mkdir)
        files = [f for f in out_dir.rglob("*") if f.is_file()] if out_dir.exists() else []
        assert len(files) == 0

    def test_dry_run_shows_all_six_paths(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(FULL_YAML)
        out_dir = tmp_path / "gen"

        result = runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--out", str(out_dir),
            "--dry-run",
        ])
        assert result.output.count("would write") == 6

    def test_missing_descriptor_shows_error(self, tmp_path):
        result = runner.invoke(app, [
            "--descriptor", str(tmp_path / "nonexistent.yaml"),
        ])
        assert result.exit_code != 0

    def test_output_contains_loaded_message(self, tmp_path):
        desc_path = tmp_path / "hwip.yaml"
        desc_path.write_text(MINIMAL_YAML)

        result = runner.invoke(app, [
            "--descriptor", str(desc_path),
            "--dry-run",
        ])
        assert "Loaded" in result.output
        assert "hwip=accel" in result.output
