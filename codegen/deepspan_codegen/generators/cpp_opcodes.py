# SPDX-License-Identifier: Apache-2.0
"""Generate gen/rpc/<hwip_name>.hpp — C++20 opcode constants."""

from pathlib import Path

from .base import BaseGenerator


class CppOpcodesGenerator(BaseGenerator):
    """Generates gen/rpc/<hwip_name>.hpp (C++20 enum class + mapping helpers)."""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "rpc" / f"{self.desc.name}.hpp"
        content = self._render("cpp_opcodes.hpp.j2")
        return [self._write(out, content, dry_run)]
