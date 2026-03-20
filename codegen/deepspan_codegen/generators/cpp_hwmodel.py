# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class CppHwModelGenerator(BaseGenerator):
    """Generates gen/sim/deepspan_<type>/ops.hpp"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "sim" / f"deepspan_{self.desc.name}" / "ops.hpp"
        content = self._render("cpp_hwmodel.hpp.j2")
        return [self._write(out, content, dry_run)]
