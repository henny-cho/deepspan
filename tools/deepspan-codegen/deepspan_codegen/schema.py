# SPDX-License-Identifier: Apache-2.0
"""Pydantic v2 schema for hwip.yaml descriptor files."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class BitField(BaseModel):
    name: str
    pos: int = Field(ge=0, lt=32)
    width: int = Field(default=1, ge=1)
    doc: str = ""


class RegisterDef(BaseModel):
    name: str
    offset: int = Field(ge=0)
    size: Literal[8, 16, 32, 64] = 32
    access: Literal["ro", "rw", "wo", "w1c"] = "rw"
    bits: list[BitField] = []
    doc: str = ""

    @field_validator("offset", mode="before")
    @classmethod
    def _parse_hex(cls, v: object) -> int:
        if isinstance(v, str):
            return int(v, 0)
        return int(v)


class RegisterBank(BaseModel):
    """Named group of registers (e.g. control_bank, command_bank)."""

    __pydantic_extra__: dict[str, list[RegisterDef]] = {}

    model_config = {"extra": "allow"}

    def registers(self) -> list[RegisterDef]:
        """Flatten all register lists from all bank groups."""
        result: list[RegisterDef] = []
        for v in self.__pydantic_extra__.values():
            result.extend(v)
        return result


class PlatformRegisters(BaseModel):
    total_size: int = Field(default=0x200, ge=0)
    control_bank: list[RegisterDef] = []
    command_bank: list[RegisterDef] = []
    result_bank: list[RegisterDef] = []

    @field_validator("total_size", mode="before")
    @classmethod
    def _parse_hex(cls, v: object) -> int:
        if isinstance(v, str):
            return int(v, 0)
        return int(v)

    def all_registers(self) -> list[RegisterDef]:
        return self.control_bank + self.command_bank + self.result_bank


class OpField(BaseModel):
    name: str
    type: Literal["u8", "u16", "u32", "u64", "bytes", "string"] = "u32"
    max_bytes: int | None = None
    maps_to: str | None = None  # register name
    doc: str = ""


class OpRequest(BaseModel):
    encoding: Literal["fixed_args", "dma_bytes", "none"] = "fixed_args"
    fields: list[OpField] = []


class OpResponse(BaseModel):
    fields: list[OpField] = []


class OperationDef(BaseModel):
    name: str
    opcode: int
    proto_enum_value: int
    doc: str = ""
    request: OpRequest = Field(default_factory=OpRequest)
    response: OpResponse = Field(default_factory=OpResponse)

    @field_validator("opcode", mode="before")
    @classmethod
    def _parse_hex(cls, v: object) -> int:
        if isinstance(v, str):
            return int(v, 0)
        return int(v)

    @property
    def name_upper(self) -> str:
        return self.name.upper()

    @property
    def name_camel(self) -> str:
        return self.name.title().replace("_", "")


class HwipDescriptor(BaseModel):
    """Root descriptor loaded from hwip.yaml."""

    name: str = Field(min_length=1)
    version: str = "0.1.0"
    namespace: str = ""

    platform_registers: PlatformRegisters = Field(default_factory=PlatformRegisters)
    operations: list[OperationDef] = []

    @model_validator(mode="after")
    def _default_namespace(self) -> "HwipDescriptor":
        if not self.namespace:
            self.namespace = f"deepspan_{self.name}"
        return self

    @property
    def name_upper(self) -> str:
        return self.name.upper()

    @property
    def name_camel(self) -> str:
        return self.name.title().replace("_", "")


def load_descriptor(path: str) -> HwipDescriptor:
    """Load and validate an hwip.yaml file."""
    import yaml  # type: ignore[import-untyped]

    with open(path, encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    hwip_raw = raw.get("hwip", raw)
    return HwipDescriptor.model_validate(hwip_raw)
