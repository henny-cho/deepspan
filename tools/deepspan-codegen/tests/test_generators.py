# SPDX-License-Identifier: Apache-2.0
"""Integration tests: generate all targets from a minimal descriptor."""

import textwrap
from pathlib import Path

import pytest

from deepspan_codegen.schema import load_descriptor
from deepspan_codegen.generators.c_kernel import CKernelGenerator
from deepspan_codegen.generators.cpp_hwmodel import CppHwModelGenerator
from deepspan_codegen.generators.c_firmware import CFirmwareGenerator
from deepspan_codegen.generators.proto import ProtoGenerator
from deepspan_codegen.generators.go_opcodes import GoOpcodesGenerator
from deepspan_codegen.generators.python_sdk import PythonSdkGenerator


MINIMAL_YAML = textwrap.dedent("""
    hwip:
      name: accel
      version: "1.0.0"
      platform_registers:
        total_size: 0x200
        control_bank:
          - { name: ctrl, offset: 0x000, access: rw,
              bits: [{name: RESET, pos: 0}, {name: START, pos: 1}] }
        command_bank:
          - { name: cmd_opcode, offset: 0x100, access: wo }
          - { name: cmd_arg0,   offset: 0x104, access: wo }
        result_bank:
          - { name: result_data0, offset: 0x114, access: ro }
      operations:
        - name: echo
          opcode: 0x0001
          proto_enum_value: 1
          doc: "Echo test"
          request:
            encoding: fixed_args
            fields: [{ name: arg0, type: u32 }, { name: arg1, type: u32 }]
          response:
            fields: [{ name: data0, type: u32 }]
""")


@pytest.fixture
def desc(tmp_path):
    p = tmp_path / "hwip.yaml"
    p.write_text(MINIMAL_YAML)
    return load_descriptor(str(p))


def test_c_kernel(desc, tmp_path):
    gen = CKernelGenerator(desc, tmp_path / "gen")
    files = gen.generate()
    assert len(files) == 1
    content = files[0].read_text()
    assert "DEEPSPAN_ACCEL_OP_ECHO" in content
    assert "0x0001U" in content
    assert "DEEPSPAN_ACCEL_REG_CMD_OPCODE" in content


def test_cpp_hwmodel(desc, tmp_path):
    gen = CppHwModelGenerator(desc, tmp_path / "gen")
    files = gen.generate()
    content = files[0].read_text()
    assert "enum class AccelOp" in content
    assert "ECHO = 0x0001U" in content


def test_proto(desc, tmp_path):
    gen = ProtoGenerator(desc, tmp_path / "gen")
    files = gen.generate()
    content = files[0].read_text()
    assert "ACCEL_OP_UNSPECIFIED = 0" in content
    assert "ACCEL_OP_ECHO = 1" in content
    assert "service AccelHwipService" in content


def test_go_opcodes(desc, tmp_path):
    gen = GoOpcodesGenerator(desc, tmp_path / "gen")
    files = gen.generate()
    content = files[0].read_text()
    assert "OpEcho uint32 = 0x0001U" in content
    assert "AccelOpToHwOpcode" in content


def test_python_sdk(desc, tmp_path):
    gen = PythonSdkGenerator(desc, tmp_path / "gen")
    files = gen.generate()
    content = files[0].read_text()
    assert "class AccelOp(IntEnum)" in content
    assert "ECHO = 0x1" in content
    assert "class EchoRequest(BaseModel)" in content
