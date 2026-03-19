# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class CFirmwareGenerator(BaseGenerator):
    """Generates gen/firmware/deepspan_<type>/dispatch.h"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "firmware" / f"deepspan_{self.desc.name}" / "dispatch.h"
        content = self._render("c_firmware.h.j2")
        return [self._write(out, content, dry_run)]
