# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class CKernelGenerator(BaseGenerator):
    """Generates gen/kernel/deepspan_<type>.h"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "kernel" / f"deepspan_{self.desc.name}.h"
        content = self._render("c_kernel.h.j2")
        return [self._write(out, content, dry_run)]
