# SPDX-License-Identifier: Apache-2.0
"""Tests for hwip.yaml schema validation."""

import textwrap

import pytest
import yaml

from deepspan_codegen.schema import HwipDescriptor, load_descriptor


ACCEL_YAML = textwrap.dedent("""
    hwip:
      name: accel
      version: "1.0.0"
      namespace: deepspan_accel
      platform_registers:
        total_size: 0x200
        control_bank:
          - { name: ctrl,       offset: 0x000, size: 32, access: rw,
              bits: [{name: RESET, pos: 0}, {name: START, pos: 1}] }
          - { name: status,     offset: 0x004, size: 32, access: ro }
        command_bank:
          - { name: cmd_opcode, offset: 0x100, size: 32, access: wo }
          - { name: cmd_arg0,   offset: 0x104, size: 32, access: wo }
        result_bank:
          - { name: result_status, offset: 0x110, size: 32, access: ro }
          - { name: result_data0,  offset: 0x114, size: 32, access: ro }
      operations:
        - name: echo
          opcode: 0x0001
          proto_enum_value: 1
          doc: "Echo arg0 back"
          request:
            encoding: fixed_args
            fields:
              - { name: arg0, type: u32 }
              - { name: arg1, type: u32 }
          response:
            fields:
              - { name: data0, type: u32, maps_to: result_data0 }
        - name: status
          opcode: 0x0003
          proto_enum_value: 3
          request:
            encoding: fixed_args
            fields: []
          response:
            fields:
              - { name: status_word, type: u32 }
""")


def test_load_accel_descriptor(tmp_path):
    p = tmp_path / "hwip.yaml"
    p.write_text(ACCEL_YAML)
    desc = load_descriptor(str(p))
    assert desc.name == "accel"
    assert desc.version == "1.0.0"
    assert len(desc.operations) == 2
    assert desc.operations[0].opcode == 0x0001
    assert desc.operations[0].name == "echo"


def test_register_offsets(tmp_path):
    p = tmp_path / "hwip.yaml"
    p.write_text(ACCEL_YAML)
    desc = load_descriptor(str(p))
    regs = desc.platform_registers.all_registers()
    names = [r.name for r in regs]
    assert "cmd_opcode" in names
    assert "result_data0" in names


def test_default_namespace(tmp_path):
    yaml_str = "hwip:\n  name: myip\n"
    p = tmp_path / "hwip.yaml"
    p.write_text(yaml_str)
    desc = load_descriptor(str(p))
    assert desc.namespace == "deepspan_myip"
