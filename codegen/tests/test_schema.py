# SPDX-License-Identifier: Apache-2.0
"""TDD tests for hwip.yaml schema validation."""

import textwrap

import pytest
from pydantic import ValidationError

from deepspan_codegen.schema import (
    BitField, HwipDescriptor, OperationDef, RegisterDef, load_descriptor,
)
from tests.conftest import FULL_YAML, MINIMAL_YAML


# ── load_descriptor ───────────────────────────────────────────────────────────

class TestLoadDescriptor:
    def test_flat_yaml(self, tmp_path):
        """Flat YAML (no hwip: sub-section) is accepted."""
        p = tmp_path / "hwip.yaml"
        p.write_text("name: myip\nversion: '0.2.0'\n")
        desc = load_descriptor(str(p))
        assert desc.name == "myip"
        assert desc.version == "0.2.0"

    def test_sectioned_yaml(self, tmp_path):
        """Sectioned YAML (hwip: + top-level registers/ops) is accepted."""
        p = tmp_path / "hwip.yaml"
        p.write_text(FULL_YAML)
        desc = load_descriptor(str(p))
        assert desc.name == "accel"
        assert len(desc.operations) == 3
        # 6 control + 4 command + 3 result = 13 registers
        assert len(desc.platform_registers.all_registers()) == 13

    def test_minimal_yaml(self, tmp_path):
        """Minimal YAML (name only) works with all defaults."""
        p = tmp_path / "hwip.yaml"
        p.write_text(MINIMAL_YAML)
        desc = load_descriptor(str(p))
        assert desc.name == "accel"
        assert desc.version == "1.0.0"
        assert len(desc.operations) == 1

    def test_default_namespace_from_name(self, tmp_path):
        """namespace defaults to deepspan_<name> if not set."""
        p = tmp_path / "hwip.yaml"
        p.write_text("name: myip\n")
        desc = load_descriptor(str(p))
        assert desc.namespace == "deepspan_myip"

    def test_explicit_namespace_preserved(self, tmp_path):
        """Explicit namespace is kept as-is."""
        p = tmp_path / "hwip.yaml"
        p.write_text("name: accel\nnamespace: custom_ns\n")
        desc = load_descriptor(str(p))
        assert desc.namespace == "custom_ns"

    def test_missing_file_raises(self):
        with pytest.raises(FileNotFoundError):
            load_descriptor("/nonexistent/hwip.yaml")


# ── HwipDescriptor properties ─────────────────────────────────────────────────

class TestHwipDescriptorProperties:
    def test_name_upper(self, full_desc):
        assert full_desc.name_upper == "ACCEL"

    def test_name_camel(self, full_desc):
        assert full_desc.name_camel == "Accel"

    def test_multiword_name_camel(self, tmp_path):
        # "my_ip".title() == "My_Ip", then replace("_","") == "MyIp"
        p = tmp_path / "hwip.yaml"
        p.write_text("name: my_ip\n")
        desc = load_descriptor(str(p))
        assert desc.name_camel == "MyIp"

    def test_operations_count(self, full_desc):
        assert len(full_desc.operations) == 3

    def test_operation_names(self, full_desc):
        names = [op.name for op in full_desc.operations]
        assert names == ["echo", "process", "status"]


# ── RegisterDef ───────────────────────────────────────────────────────────────

class TestRegisterDef:
    def test_hex_offset_string(self):
        r = RegisterDef(name="ctrl", offset="0x000", access="rw")
        assert r.offset == 0

    def test_hex_offset_large(self):
        r = RegisterDef(name="cmd", offset="0x100", access="wo")
        assert r.offset == 0x100

    def test_decimal_offset(self):
        r = RegisterDef(name="r", offset=256, access="ro")
        assert r.offset == 256

    def test_default_size(self):
        r = RegisterDef(name="r", offset=0, access="rw")
        assert r.size == 32

    def test_access_modes(self):
        for mode in ("ro", "rw", "wo", "w1c"):
            r = RegisterDef(name="r", offset=0, access=mode)
            assert r.access == mode

    def test_invalid_access_raises(self):
        with pytest.raises(ValidationError):
            RegisterDef(name="r", offset=0, access="invalid")

    def test_invalid_size_raises(self):
        with pytest.raises(ValidationError):
            RegisterDef(name="r", offset=0, size=7)

    def test_bit_fields_attached(self):
        r = RegisterDef(name="ctrl", offset=0, bits=[
            BitField(name="RESET", pos=0),
            BitField(name="START", pos=1),
        ])
        assert len(r.bits) == 2
        assert r.bits[0].name == "RESET"
        assert r.bits[1].pos == 1


# ── PlatformRegisters ─────────────────────────────────────────────────────────

class TestPlatformRegisters:
    def test_all_registers_flat(self, full_desc):
        regs = full_desc.platform_registers.all_registers()
        names = [r.name for r in regs]
        # control_bank first, then command_bank, then result_bank
        assert names.index("ctrl") < names.index("cmd_opcode")
        assert names.index("cmd_opcode") < names.index("result_status")

    def test_all_register_names(self, full_desc):
        names = {r.name for r in full_desc.platform_registers.all_registers()}
        assert names >= {"ctrl", "cmd_opcode", "cmd_arg0", "result_data0", "result_data1"}

    def test_total_size_hex(self, full_desc):
        assert full_desc.platform_registers.total_size == 0x200

    def test_register_offset_values(self, full_desc):
        regs = {r.name: r.offset for r in full_desc.platform_registers.all_registers()}
        assert regs["ctrl"] == 0x000
        assert regs["cmd_opcode"] == 0x100
        assert regs["result_data0"] == 0x114


# ── OperationDef ──────────────────────────────────────────────────────────────

class TestOperationDef:
    def test_hex_opcode_string(self, full_desc):
        echo = full_desc.operations[0]
        assert echo.opcode == 0x0001

    def test_name_upper(self, full_desc):
        assert full_desc.operations[0].name_upper == "ECHO"

    def test_name_camel(self, full_desc):
        assert full_desc.operations[0].name_camel == "Echo"

    def test_proto_enum_values_sequential(self, full_desc):
        values = [op.proto_enum_value for op in full_desc.operations]
        assert values == [1, 2, 3]

    def test_proto_enum_never_zero(self, full_desc):
        """proto3 requires 0 to be UNSPECIFIED — no op may use 0."""
        for op in full_desc.operations:
            assert op.proto_enum_value != 0

    def test_request_fields(self, full_desc):
        echo = full_desc.operations[0]
        assert echo.request.encoding == "fixed_args"
        assert len(echo.request.fields) == 2
        assert echo.request.fields[0].name == "arg0"

    def test_response_fields(self, full_desc):
        echo = full_desc.operations[0]
        assert len(echo.response.fields) == 2
        assert echo.response.fields[0].maps_to == "result_data0"

    def test_empty_request_fields(self, full_desc):
        status_op = full_desc.operations[2]
        assert status_op.request.fields == []

    def test_bytes_field_max(self, full_desc):
        process_op = full_desc.operations[1]
        data_field = process_op.request.fields[0]
        assert data_field.type == "bytes"
        assert data_field.max_bytes == 4096
