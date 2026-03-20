# SPDX-License-Identifier: Apache-2.0
"""CLI entry point for deepspan-codegen."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from .schema import load_descriptor
from .generators.c_kernel import CKernelGenerator
from .generators.cpp_hwmodel import CppHwModelGenerator
from .generators.c_firmware import CFirmwareGenerator
from .generators.proto import ProtoGenerator
from .generators.cpp_opcodes import CppOpcodesGenerator
from .generators.python_sdk import PythonSdkGenerator

app = typer.Typer(
    name="deepspan-codegen",
    help="Generate HWIP API artifacts from hwip.yaml descriptor.",
    no_args_is_help=True,
)
console = Console()

# Targets and their output subdirs:
#   kernel   → gen/kernel/     (C header for Linux driver)
#   firmware → gen/firmware/   (C header for Zephyr firmware)
#   hw_model → gen/sim/        (C++20 header for hw-model simulator)
#   rpc      → gen/rpc/        (C++20 opcode constants, replaces Go go_opcodes)
#   proto    → gen/proto/      (Protobuf .proto service definition)
#   python   → gen/sdk/        (Python Pydantic models)
ALL_TARGETS = ["kernel", "firmware", "hw_model", "rpc", "proto", "python"]

GENERATORS = {
    "kernel":   CKernelGenerator,
    "firmware": CFirmwareGenerator,
    "hw_model": CppHwModelGenerator,
    "rpc":      CppOpcodesGenerator,
    "proto":    ProtoGenerator,
    "python":   PythonSdkGenerator,
}


@app.command()
def generate(
    descriptor: Annotated[
        Path,
        typer.Option("--descriptor", "-d", help="Path to hwip.yaml", exists=True),
    ],
    out: Annotated[
        Path,
        typer.Option("--out", "-o", help="Output directory root"),
    ] = Path("gen"),
    target: Annotated[
        str,
        typer.Option("--target", "-t", help=f"Target(s): all or comma-separated from {ALL_TARGETS}"),
    ] = "all",
    dry_run: Annotated[
        bool,
        typer.Option("--dry-run", help="Print files that would be generated without writing"),
    ] = False,
) -> None:
    """Generate HWIP API artifacts from a hwip.yaml descriptor."""
    desc = load_descriptor(str(descriptor))
    console.print(f"[green]Loaded[/] {descriptor} — hwip={desc.name} v{desc.version}")

    targets = ALL_TARGETS if target == "all" else [t.strip() for t in target.split(",")]
    unknown = set(targets) - set(ALL_TARGETS)
    if unknown:
        console.print(f"[red]Unknown targets:[/] {unknown}. Valid: {ALL_TARGETS}")
        raise typer.Exit(1)

    out.mkdir(parents=True, exist_ok=True)

    for t in targets:
        gen = GENERATORS[t](desc, out)
        files = gen.generate(dry_run=dry_run)
        for f in files:
            action = "would write" if dry_run else "wrote"
            console.print(f"  [{t}] {action}: {f}")

    console.print("[bold green]Done.[/]")


if __name__ == "__main__":
    app()
