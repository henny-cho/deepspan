# SPDX-License-Identifier: Apache-2.0
"""Shared pytest fixtures for deepspan-codegen tests."""

import textwrap
from pathlib import Path

import pytest

from deepspan_codegen.schema import load_descriptor

# ── Canonical YAML fixtures ──────────────────────────────────────────────────

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
          doc: "Echo arg0/arg1 back"
          request:
            encoding: fixed_args
            fields:
              - { name: arg0, type: u32 }
              - { name: arg1, type: u32 }
          response:
            fields:
              - { name: data0, type: u32, maps_to: result_data0 }
""")

FULL_YAML = textwrap.dedent("""
    hwip:
      name: accel
      version: "1.0.0"
      namespace: deepspan_accel

    platform_registers:
      total_size: 0x200
      control_bank:
        - { name: ctrl,         offset: 0x000, access: rw,
            bits: [{name: RESET, pos: 0}, {name: START, pos: 1}, {name: IRQ_CLR, pos: 2}] }
        - { name: status,       offset: 0x004, access: ro,
            bits: [{name: READY, pos: 0}, {name: BUSY, pos: 1}, {name: ERROR, pos: 2}] }
        - { name: irq_status,   offset: 0x008, access: w1c,
            bits: [{name: DONE, pos: 0}] }
        - { name: irq_enable,   offset: 0x00C, access: rw }
        - { name: version,      offset: 0x010, access: ro }
        - { name: capabilities, offset: 0x014, access: ro,
            bits: [{name: DMA, pos: 0}, {name: IRQ, pos: 1}, {name: MULTI, pos: 2}] }
      command_bank:
        - { name: cmd_opcode, offset: 0x100, access: wo }
        - { name: cmd_arg0,   offset: 0x104, access: wo }
        - { name: cmd_arg1,   offset: 0x108, access: wo }
        - { name: cmd_flags,  offset: 0x10C, access: wo }
      result_bank:
        - { name: result_status, offset: 0x110, access: ro }
        - { name: result_data0,  offset: 0x114, access: ro }
        - { name: result_data1,  offset: 0x118, access: ro }

    operations:
      - name: echo
        opcode: 0x0001
        proto_enum_value: 1
        doc: "Echo arg0/arg1 back as result — latency test"
        request:
          encoding: fixed_args
          fields:
            - { name: arg0, type: u32 }
            - { name: arg1, type: u32 }
        response:
          fields:
            - { name: data0, type: u32, maps_to: result_data0 }
            - { name: data1, type: u32, maps_to: result_data1 }
      - name: process
        opcode: 0x0002
        proto_enum_value: 2
        doc: "Run data processing pipeline"
        request:
          encoding: dma_bytes
          fields:
            - { name: data, type: bytes, max_bytes: 4096 }
        response:
          fields:
            - { name: result, type: bytes }
      - name: status
        opcode: 0x0003
        proto_enum_value: 3
        doc: "Return device status word"
        request:
          encoding: fixed_args
          fields: []
        response:
          fields:
            - { name: status_word, type: u32, maps_to: result_data0 }
""")


@pytest.fixture
def minimal_desc(tmp_path):
    """Minimal one-operation descriptor."""
    p = tmp_path / "hwip.yaml"
    p.write_text(MINIMAL_YAML)
    return load_descriptor(str(p))


@pytest.fixture
def full_desc(tmp_path):
    """Full accel descriptor with all 3 operations and all registers."""
    p = tmp_path / "hwip.yaml"
    p.write_text(FULL_YAML)
    return load_descriptor(str(p))


@pytest.fixture
def minimal_yaml_path(tmp_path):
    p = tmp_path / "hwip.yaml"
    p.write_text(MINIMAL_YAML)
    return p


@pytest.fixture
def full_yaml_path(tmp_path):
    p = tmp_path / "hwip.yaml"
    p.write_text(FULL_YAML)
    return p
