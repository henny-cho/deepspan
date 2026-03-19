# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class GoOpcodesGenerator(BaseGenerator):
    """Generates gen/server/deepspan_<type>/opcodes.go"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "server" / f"deepspan_{self.desc.name}" / "opcodes.go"
        content = self._render("go_opcodes.go.j2")
        return [self._write(out, content, dry_run)]
