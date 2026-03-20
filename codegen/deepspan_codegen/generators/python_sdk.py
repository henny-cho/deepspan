# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class PythonSdkGenerator(BaseGenerator):
    """Generates gen/l6-sdk/deepspan_<type>/models.py"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "l6-sdk" / f"deepspan_{self.desc.name}" / "models.py"
        content = self._render("python_sdk.py.j2")
        return [self._write(out, content, dry_run)]
