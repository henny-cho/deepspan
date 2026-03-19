# SPDX-License-Identifier: Apache-2.0
from pathlib import Path
from .base import BaseGenerator


class PythonSdkGenerator(BaseGenerator):
    """Generates gen/sdk/deepspan_<type>/models.py"""

    def generate(self, dry_run: bool = False) -> list[Path]:
        out = self.out_dir / "sdk" / f"deepspan_{self.desc.name}" / "models.py"
        content = self._render("python_sdk.py.j2")
        return [self._write(out, content, dry_run)]
