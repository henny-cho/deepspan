# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class ProtoGenerator(BaseGenerator):
    """Generates gen/l5-proto/deepspan_<type>/v1/device.proto"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "l5-proto" / f"deepspan_{self.desc.name}" / "v1" / "device.proto"
        content = self._render("device.proto.j2")
        return [self._write(out, content, dry_run)]
