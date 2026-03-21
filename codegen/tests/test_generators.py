# SPDX-License-Identifier: Apache-2.0
"""TDD tests for each code generator target."""

import re
from pathlib import Path

import pytest

from deepspan_codegen.generators.c_firmware import CFirmwareGenerator
from deepspan_codegen.generators.c_kernel import CKernelGenerator
from deepspan_codegen.generators.cpp_hwmodel import CppHwModelGenerator
from deepspan_codegen.generators.cpp_opcodes import CppOpcodesGenerator
from deepspan_codegen.generators.proto import ProtoGenerator
from deepspan_codegen.generators.python_sdk import PythonSdkGenerator


# ── Helpers ───────────────────────────────────────────────────────────────────

def _gen(cls, desc, tmp_path) -> str:
    gen = cls(desc, tmp_path / "gen")
    files = gen.generate()
    assert len(files) == 1, f"Expected 1 file, got {len(files)}"
    return files[0].read_text()


def _gen_path(cls, desc, tmp_path) -> Path:
    gen = cls(desc, tmp_path / "gen")
    files = gen.generate()
    return files[0]


# ── C Kernel Generator ────────────────────────────────────────────────────────

class TestCKernelGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(CKernelGenerator, minimal_desc, tmp_path)
        assert p.name == "deepspan_accel.h"
        assert "kernel" in str(p)

    def test_include_guard(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "#ifndef DEEPSPAN_ACCEL_H" in c
        assert "#define DEEPSPAN_ACCEL_H" in c
        assert "#endif /* DEEPSPAN_ACCEL_H */" in c

    def test_opcode_macros(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "#define DEEPSPAN_ACCEL_OP_ECHO    0x0001U" in c

    def test_register_offset_macros(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_REG_CMD_OPCODE" in c
        assert "0x0100U" in c

    def test_bit_field_macros(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_CTRL_RESET" in c
        assert "(1U << 0)" in c
        assert "DEEPSPAN_ACCEL_CTRL_START" in c
        assert "(1U << 1)" in c

    def test_valid_op_macro(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_IS_VALID_OP" in c
        assert "0x0001U" in c

    def test_request_struct(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "struct deepspan_accel_echo_req" in c
        assert "__u32 arg0;" in c
        assert "__u32 arg1;" in c

    def test_response_struct(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "struct deepspan_accel_echo_resp" in c
        assert "__u32 data0;" in c

    def test_all_opcodes_in_full(self, full_desc, tmp_path):
        c = _gen(CKernelGenerator, full_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_OP_ECHO" in c
        assert "DEEPSPAN_ACCEL_OP_PROCESS" in c
        assert "DEEPSPAN_ACCEL_OP_STATUS" in c

    def test_all_registers_in_full(self, full_desc, tmp_path):
        c = _gen(CKernelGenerator, full_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_REG_CMD_ARG0" in c
        assert "DEEPSPAN_ACCEL_REG_RESULT_DATA1" in c
        assert "DEEPSPAN_ACCEL_REG_VERSION" in c

    def test_auto_generated_header(self, minimal_desc, tmp_path):
        c = _gen(CKernelGenerator, minimal_desc, tmp_path)
        assert "AUTO-GENERATED" in c
        assert "DO NOT EDIT" in c

    def test_dry_run_no_file(self, minimal_desc, tmp_path):
        gen = CKernelGenerator(minimal_desc, tmp_path / "gen")
        files = gen.generate(dry_run=True)
        assert len(files) == 1
        assert not files[0].exists()


# ── C++ HW Model Generator ────────────────────────────────────────────────────

class TestCppHwModelGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(CppHwModelGenerator, minimal_desc, tmp_path)
        assert p.name == "ops.hpp"
        assert "deepspan_accel" in str(p)

    def test_namespace(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "namespace deepspan::accel {" in c
        assert "}  // namespace deepspan::accel" in c

    def test_pragma_once(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "#pragma once" in c

    def test_enum_class(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "enum class AccelOp : uint32_t {" in c
        assert "ECHO = 0x0001U," in c

    def test_reg_offsets_struct(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "struct RegOffsets {" in c
        assert "static constexpr uint32_t CMD_OPCODE = 0x0100U;" in c

    def test_bit_struct(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "struct CtrlBits {" in c
        assert "static constexpr uint32_t RESET = (1U << 0);" in c

    def test_request_struct(self, minimal_desc, tmp_path):
        c = _gen(CppHwModelGenerator, minimal_desc, tmp_path)
        assert "struct EchoRequest {" in c
        assert "uint32_t arg0{};" in c

    def test_all_ops_full(self, full_desc, tmp_path):
        c = _gen(CppHwModelGenerator, full_desc, tmp_path)
        assert "ECHO = 0x0001U," in c
        assert "PROCESS = 0x0002U," in c
        assert "STATUS = 0x0003U," in c


# ── C Firmware Generator ──────────────────────────────────────────────────────

class TestCFirmwareGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(CFirmwareGenerator, minimal_desc, tmp_path)
        assert p.name == "dispatch.h"
        assert "deepspan_accel" in str(p)

    def test_include_guard(self, minimal_desc, tmp_path):
        c = _gen(CFirmwareGenerator, minimal_desc, tmp_path)
        assert "#ifndef DEEPSPAN_ACCEL_DISPATCH_H" in c
        assert "#endif" in c

    def test_is_valid_op_inline(self, minimal_desc, tmp_path):
        c = _gen(CFirmwareGenerator, minimal_desc, tmp_path)
        assert "deepspan_accel_is_valid_op" in c
        assert "switch (op)" in c

    def test_dispatch_function_decl(self, minimal_desc, tmp_path):
        c = _gen(CFirmwareGenerator, minimal_desc, tmp_path)
        assert "deepspan_accel_dispatch(" in c

    def test_all_opcodes_in_switch(self, full_desc, tmp_path):
        c = _gen(CFirmwareGenerator, full_desc, tmp_path)
        assert "DEEPSPAN_ACCEL_OP_ECHO" in c
        assert "DEEPSPAN_ACCEL_OP_PROCESS" in c
        assert "DEEPSPAN_ACCEL_OP_STATUS" in c


# ── Proto Generator ───────────────────────────────────────────────────────────

class TestProtoGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(ProtoGenerator, minimal_desc, tmp_path)
        assert p.name == "device.proto"
        assert "v1" in str(p)

    def test_proto3_syntax(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert 'syntax = "proto3";' in c

    def test_package_declaration(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "package deepspan_accel.v1;" in c

    def test_go_package_option(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "option go_package" in c
        assert "deepspan-hwip/accel" in c

    def test_unspecified_enum_value_zero(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "ACCEL_OP_UNSPECIFIED = 0;" in c

    def test_echo_enum_value(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "ACCEL_OP_ECHO = 1;" in c

    def test_request_message(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "message EchoRequest {" in c
        assert "string device_id = 1;" in c
        assert "uint32 arg0 = 2;" in c

    def test_response_message(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "message EchoResponse {" in c
        assert "int32 status = 1;" in c

    def test_service_definition(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "service AccelHwipService {" in c
        assert "rpc Echo(EchoRequest) returns (EchoResponse);" in c

    def test_submit_request_backwards_compat(self, minimal_desc, tmp_path):
        c = _gen(ProtoGenerator, minimal_desc, tmp_path)
        assert "rpc SubmitRequest(" in c

    def test_all_ops_in_service(self, full_desc, tmp_path):
        c = _gen(ProtoGenerator, full_desc, tmp_path)
        assert "rpc Echo(" in c
        assert "rpc Process(" in c
        assert "rpc Status(" in c

    def test_all_ops_in_enum(self, full_desc, tmp_path):
        c = _gen(ProtoGenerator, full_desc, tmp_path)
        assert "ACCEL_OP_ECHO = 1;" in c
        assert "ACCEL_OP_PROCESS = 2;" in c
        assert "ACCEL_OP_STATUS = 3;" in c


# ── C++ Opcodes Generator ─────────────────────────────────────────────────────

class TestCppOpcodesGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert p.name == "accel.hpp"
        assert "rpc" in str(p)

    def test_namespace(self, minimal_desc, tmp_path):
        c = _gen(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert "namespace deepspan_accel" in c

    def test_opcode_constant_cpp_syntax(self, minimal_desc, tmp_path):
        """C++ uses 0x0001U with U suffix."""
        c = _gen(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert "ECHO = 0x0001U" in c

    def test_register_constant_cpp_syntax(self, minimal_desc, tmp_path):
        """Register offsets use UPPER_CASE with U suffix."""
        c = _gen(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert "CMD_OPCODE = 0x0100U" in c

    def test_proto_op_to_hw_op_function(self, minimal_desc, tmp_path):
        c = _gen(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert "proto_op_to_hw_op" in c
        assert "case 1:" in c
        assert "Op::ECHO" in c

    def test_validate_opcode_function(self, minimal_desc, tmp_path):
        c = _gen(CppOpcodesGenerator, minimal_desc, tmp_path)
        assert "validate_opcode" in c
        assert "Op::ECHO" in c
        assert "return true" in c

    def test_validate_opcode_multi(self, full_desc, tmp_path):
        """With 3 ops, validate_opcode has all three Op:: cases."""
        c = _gen(CppOpcodesGenerator, full_desc, tmp_path)
        assert "Op::ECHO" in c
        assert "Op::PROCESS" in c
        assert "Op::STATUS" in c

    def test_unspecified_returns_false(self, full_desc, tmp_path):
        """Unknown proto_op must return {0, false}."""
        c = _gen(CppOpcodesGenerator, full_desc, tmp_path)
        assert "default:" in c
        assert "return {0u, false}" in c

    def test_all_ops_present(self, full_desc, tmp_path):
        c = _gen(CppOpcodesGenerator, full_desc, tmp_path)
        assert "ECHO = 0x0001U" in c
        assert "PROCESS = 0x0002U" in c
        assert "STATUS = 0x0003U" in c


# ── Python SDK Generator ──────────────────────────────────────────────────────

class TestPythonSdkGenerator:
    def test_output_path(self, minimal_desc, tmp_path):
        p = _gen_path(PythonSdkGenerator, minimal_desc, tmp_path)
        assert p.name == "models.py"
        assert "deepspan_accel" in str(p)

    def test_intenum_class(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "class AccelOp(IntEnum):" in c
        assert "ECHO = 0x1" in c

    def test_pydantic_request_model(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "class EchoRequest(BaseModel):" in c
        assert "arg0: int = Field" in c
        assert "arg1: int = Field" in c

    def test_uint32_field_bounds(self, minimal_desc, tmp_path):
        """u32 fields must use ge=0, lt=2**32 bounds."""
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "ge=0, lt=2**32" in c

    def test_encode_payload_for_fixed_args(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "def encode_payload(self) -> bytes:" in c
        assert "struct.pack" in c

    def test_pydantic_response_model(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "class EchoResponse(BaseModel):" in c
        assert "data0: int = 0" in c

    def test_accel_client_class(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "class AccelClient:" in c
        assert 'hwip_type: str = "accel"' in c

    def test_client_echo_method(self, minimal_desc, tmp_path):
        c = _gen(PythonSdkGenerator, minimal_desc, tmp_path)
        assert "def echo(" in c
        assert "arg0: int = 0" in c

    def test_all_ops_in_full(self, full_desc, tmp_path):
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert "ECHO = 0x1" in c
        assert "PROCESS = 0x2" in c
        assert "STATUS = 0x3" in c
        assert "def process(" in c
        assert "def status(" in c

    def test_bytes_field_in_process(self, full_desc, tmp_path):
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert "data: bytes = Field" in c
        assert "max_length=4096" in c

    def test_python_syntax_valid(self, full_desc, tmp_path):
        """Generated Python must be syntactically valid."""
        import ast
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        ast.parse(c)  # raises SyntaxError if invalid

    def test_echo_decode_uses_struct_unpack(self, full_desc, tmp_path):
        """echo() must decode data0/data1 from response bytes via struct.unpack_from."""
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert "struct.unpack_from" in c
        assert 'data0=struct.unpack_from("<I", _d, 0)' in c
        assert 'data1=struct.unpack_from("<I", _d, 4)' in c

    def test_status_decode_uses_struct_unpack(self, full_desc, tmp_path):
        """status() must decode status_word from result_data0 (offset 0)."""
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert 'status_word=struct.unpack_from("<I", _d, 0)' in c

    def test_process_decode_returns_raw_bytes(self, full_desc, tmp_path):
        """process() must return raw bytes as the result field."""
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert "result=_d" in c

    def test_no_decode_todo(self, full_desc, tmp_path):
        """Generated code must not contain TODO decode stubs."""
        c = _gen(PythonSdkGenerator, full_desc, tmp_path)
        assert "# TODO: decode" not in c
