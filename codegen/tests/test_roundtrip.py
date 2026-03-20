# SPDX-License-Identifier: Apache-2.0
"""Roundtrip tests: generate from full accel descriptor, verify correctness.

These tests use the same full FULL_YAML fixture that matches the committed
deepspan-hwip/accel/hwip.yaml, validating end-to-end pipeline integrity.
"""

import ast
import re
from pathlib import Path

import pytest

from deepspan_codegen.generators.c_firmware import CFirmwareGenerator
from deepspan_codegen.generators.c_kernel import CKernelGenerator
from deepspan_codegen.generators.cpp_hwmodel import CppHwModelGenerator
from deepspan_codegen.generators.cpp_opcodes import CppOpcodesGenerator
from deepspan_codegen.generators.proto import ProtoGenerator
from deepspan_codegen.generators.python_sdk import PythonSdkGenerator
from tests.conftest import FULL_YAML


@pytest.fixture
def all_generated(full_desc, tmp_path):
    """Generate all targets and return {target: content} dict."""
    out = tmp_path / "gen"
    return {
        "c_kernel":    CKernelGenerator(full_desc, out).generate()[0].read_text(),
        "cpp_hwmodel": CppHwModelGenerator(full_desc, out).generate()[0].read_text(),
        "c_firmware":  CFirmwareGenerator(full_desc, out).generate()[0].read_text(),
        "proto":       ProtoGenerator(full_desc, out).generate()[0].read_text(),
        "cpp_opcodes": CppOpcodesGenerator(full_desc, out).generate()[0].read_text(),
        "python":      PythonSdkGenerator(full_desc, out).generate()[0].read_text(),
    }


# ── Opcode value consistency across all targets ───────────────────────────────

class TestOpcodeConsistency:
    """The same opcode value 0x0001 must appear correctly in every target."""

    def test_c_kernel_echo_opcode(self, all_generated):
        assert "0x0001U" in all_generated["c_kernel"]

    def test_cpp_echo_opcode(self, all_generated):
        assert "ECHO = 0x0001U" in all_generated["cpp_hwmodel"]

    def test_cpp_opcodes_echo_opcode(self, all_generated):
        cpp = all_generated["cpp_opcodes"]
        assert "ECHO = 0x0001U" in cpp

    def test_proto_echo_enum_value_1(self, all_generated):
        """proto3 uses sequential integers, not hex wire values."""
        assert "ACCEL_OP_ECHO = 1;" in all_generated["proto"]

    def test_python_echo_hex_value(self, all_generated):
        assert "ECHO = 0x1" in all_generated["python"]

    def test_all_three_opcodes_present(self, all_generated):
        # All targets use ECHO/PROCESS/STATUS in some form
        for target in ("c_kernel", "cpp_hwmodel", "cpp_opcodes", "c_firmware", "proto", "python"):
            content = all_generated[target]
            assert "ECHO" in content, f"ECHO missing in {target}"
            assert "PROCESS" in content, f"PROCESS missing in {target}"
            assert "STATUS" in content, f"STATUS missing in {target}"


# ── Register offset consistency ───────────────────────────────────────────────

class TestRegisterConsistency:
    """cmd_opcode=0x100, result_data0=0x114 must appear correctly in all targets."""

    EXPECTED = {
        "cmd_opcode":   0x100,
        "cmd_arg0":     0x104,
        "cmd_arg1":     0x108,
        "result_data0": 0x114,
        "result_data1": 0x118,
    }

    def test_c_kernel_offsets(self, all_generated):
        c = all_generated["c_kernel"]
        assert "0x0100U" in c  # CMD_OPCODE
        assert "0x0114U" in c  # RESULT_DATA0

    def test_cpp_reg_offsets(self, all_generated):
        cpp = all_generated["cpp_hwmodel"]
        assert "CMD_OPCODE = 0x0100U" in cpp
        assert "RESULT_DATA0 = 0x0114U" in cpp
        assert "RESULT_DATA1 = 0x0118U" in cpp

    def test_cpp_opcodes_reg_constants(self, all_generated):
        cpp = all_generated["cpp_opcodes"]
        assert "CMD_OPCODE = 0x0100U" in cpp
        assert "RESULT_DATA0 = 0x0114U" in cpp

    def test_firmware_includes_kernel_header(self, all_generated):
        fw = all_generated["c_firmware"]
        assert '#include "deepspan_accel.h"' in fw


# ── Proto3 structural invariants ──────────────────────────────────────────────

class TestProtoInvariants:
    def test_unspecified_is_always_zero(self, all_generated):
        assert "ACCEL_OP_UNSPECIFIED = 0;" in all_generated["proto"]

    def test_no_opcode_uses_zero(self, full_desc, tmp_path):
        for op in full_desc.operations:
            assert op.proto_enum_value != 0, f"Op {op.name} uses proto_enum_value=0"

    def test_service_has_all_rpcs(self, all_generated):
        proto = all_generated["proto"]
        assert "rpc Echo(" in proto
        assert "rpc Process(" in proto
        assert "rpc Status(" in proto
        assert "rpc SubmitRequest(" in proto  # backwards-compat

    def test_request_has_device_id_field(self, all_generated):
        proto = all_generated["proto"]
        assert "string device_id = 1;" in proto

    def test_request_has_timeout_field(self, all_generated):
        proto = all_generated["proto"]
        assert "timeout_ms" in proto

    def test_response_has_status_field(self, all_generated):
        proto = all_generated["proto"]
        assert "int32 status = 1;" in proto


# ── C++ opcodes structural invariants ────────────────────────────────────────

class TestCppOpcodesInvariants:
    def test_proto_op_to_hw_op_all_cases(self, all_generated):
        cpp = all_generated["cpp_opcodes"]
        assert "case 1:" in cpp
        assert "case 2:" in cpp
        assert "case 3:" in cpp
        assert "return {0u, false}" in cpp

    def test_validate_opcode_all_ops(self, all_generated):
        cpp = all_generated["cpp_opcodes"]
        assert "Op::ECHO" in cpp
        assert "Op::PROCESS" in cpp
        assert "Op::STATUS" in cpp

    def test_u_suffix_present(self, all_generated):
        cpp = all_generated["cpp_opcodes"]
        assert re.search(r"0x[0-9a-fA-F]+U", cpp), \
            "C++ U suffix not found in cpp_opcodes file"


# ── Python structural invariants ──────────────────────────────────────────────

class TestPythonInvariants:
    def test_syntax_valid(self, all_generated):
        ast.parse(all_generated["python"])

    def test_imports_present(self, all_generated):
        py = all_generated["python"]
        assert "from pydantic import BaseModel, Field" in py
        assert "from enum import IntEnum" in py
        assert "import struct" in py

    def test_encode_payload_for_echo(self, all_generated):
        py = all_generated["python"]
        assert "def encode_payload" in py
        assert "struct.pack" in py

    def test_accel_client_all_methods(self, all_generated):
        py = all_generated["python"]
        assert "def echo(" in py
        assert "def process(" in py
        assert "def status(" in py

    def test_client_hwip_type_attribute(self, all_generated):
        py = all_generated["python"]
        assert 'hwip_type: str = "accel"' in py


# ── Auto-generated header present in all targets ──────────────────────────────

class TestAutoGeneratedHeaders:
    def test_all_targets_have_header(self, all_generated):
        for target, content in all_generated.items():
            assert "AUTO-GENERATED" in content, f"AUTO-GENERATED missing in {target}"
            assert "DO NOT EDIT" in content, f"DO NOT EDIT missing in {target}"
