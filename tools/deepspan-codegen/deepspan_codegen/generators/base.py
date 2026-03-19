# SPDX-License-Identifier: Apache-2.0
"""Base class for all code generators."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined

from ..schema import HwipDescriptor

TEMPLATES_DIR = Path(__file__).parent.parent / "templates"


class BaseGenerator(ABC):
    def __init__(self, desc: HwipDescriptor, out_dir: Path) -> None:
        self.desc = desc
        self.out_dir = out_dir
        self._env = Environment(
            loader=FileSystemLoader(str(TEMPLATES_DIR)),
            undefined=StrictUndefined,
            trim_blocks=True,
            lstrip_blocks=True,
        )
        self._env.filters["hex"] = lambda v: f"0x{v:04X}U"
        self._env.filters["hex_nopad"] = lambda v: f"0x{v:X}"

    @abstractmethod
    def generate(self, dry_run: bool = False) -> list[Path]:
        """Generate files and return list of written paths."""
        ...

    def _render(self, template_name: str, **ctx: object) -> str:
        tmpl = self._env.get_template(template_name)
        return tmpl.render(desc=self.desc, **ctx)

    def _write(self, path: Path, content: str, dry_run: bool) -> Path:
        if not dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        return path
