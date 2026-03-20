# SPDX-License-Identifier: Apache-2.0
import shutil
import subprocess
from pathlib import Path

from .base import BaseGenerator


class GoOpcodesGenerator(BaseGenerator):
    """Generates gen/l4-rpc/deepspan_<type>/opcodes.go (gofmt-formatted)"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "l4-rpc" / f"deepspan_{self.desc.name}" / "opcodes.go"
        content = self._render("go_opcodes.go.j2")
        content = _gofmt(content)
        return [self._write(out, content, dry_run)]


def _gofmt(src: str) -> str:
    """Run gofmt on src string; return formatted source or original on failure."""
    gofmt = shutil.which("gofmt") or "/usr/local/go/bin/gofmt"
    try:
        result = subprocess.run(
            [gofmt],
            input=src,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            return result.stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return src
