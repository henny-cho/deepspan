// SPDX-License-Identifier: Apache-2.0
// deepspan_accel/reg_map.hpp — Acceleration HWIP register layout
//
// This header specialises the generic deepspan RegMap for the accel HWIP.
// Register offsets are identical to the generic deepspan RegMap; only the
// opcode semantics (cmd_opcode field) are accel-specific.
//
// Total shared memory layout:
//   [0x000 – 0x1FF]  RegMap   (control/status/command/result registers)
//   [0x200 – 0x21F]  ShmStats (hw-model counters, start time, last opcode)
//   [0x220 – 0xFFF]  Reserved

#pragma once
#include <cstdint>

namespace deepspan::accel {

// Accel HWIP opcode values (written to RegMap::cmd_opcode).
// These are the accel-specific encoding of deepspan_req.opcode.
enum class AccelOp : uint32_t {
    ECHO    = 0x0001,  ///< Echo arg0/arg1 back as result (latency test)
    PROCESS = 0x0002,  ///< Run data processing pipeline on payload
    STATUS  = 0x0003,  ///< Return device status word in result_data0
};

// RegMap byte offsets — identical to generic deepspan hw-model RegMap.
// Defined here so accel-specific code does not depend on the generic header.
struct AccelRegOffsets {
    static constexpr uint32_t CTRL         = 0x000;
    static constexpr uint32_t STATUS       = 0x004;
    static constexpr uint32_t IRQ_STATUS   = 0x008;
    static constexpr uint32_t IRQ_ENABLE   = 0x00C;
    static constexpr uint32_t VERSION      = 0x010;
    static constexpr uint32_t CAPABILITIES = 0x014;

    // Command registers
    static constexpr uint32_t CMD_OPCODE = 0x100;
    static constexpr uint32_t CMD_ARG0   = 0x104;
    static constexpr uint32_t CMD_ARG1   = 0x108;
    static constexpr uint32_t CMD_FLAGS  = 0x10C;

    // Result registers
    static constexpr uint32_t RESULT_STATUS = 0x110;
    static constexpr uint32_t RESULT_DATA0  = 0x114;
    static constexpr uint32_t RESULT_DATA1  = 0x118;
};

// CTRL register bit definitions
struct AccelCtrlBits {
    static constexpr uint32_t RESET   = (1u << 0);  ///< Soft reset
    static constexpr uint32_t START   = (1u << 1);  ///< Start command
    static constexpr uint32_t IRQ_CLR = (1u << 2);  ///< Clear IRQ
};

// STATUS register bit definitions
struct AccelStatusBits {
    static constexpr uint32_t READY = (1u << 0);  ///< Device ready
    static constexpr uint32_t BUSY  = (1u << 1);  ///< Processing
    static constexpr uint32_t ERROR = (1u << 2);  ///< Error occurred
};

// Accel hardware capabilities bit definitions
struct AccelCapBits {
    static constexpr uint32_t DMA   = (1u << 0);  ///< DMA engine present
    static constexpr uint32_t IRQ   = (1u << 1);  ///< IRQ delivery supported
    static constexpr uint32_t MULTI = (1u << 2);  ///< Multi-device support
};

// Shared memory layout constants
struct AccelShmLayout {
    static constexpr uint32_t REGMAP_SIZE   = 0x200;  ///< RegMap region size
    static constexpr uint32_t STATS_OFFSET  = 0x200;  ///< ShmStats start offset
    static constexpr uint32_t STATS_SIZE    = 32;     ///< ShmStats region size
    static constexpr uint32_t TOTAL_SIZE    = 4096;   ///< Full shm page
};

}  // namespace deepspan::accel
