// SPDX-License-Identifier: Apache-2.0
// accel_hw_model.cpp — Accel HWIP hw-model plugin
//
// Provides opcode dispatch for the accel HWIP hw-model shared library.
// The platform hw-model server (l3/hw-model) loads this plugin to handle
// accelerator-specific opcodes via shared memory MMIO simulation.

#include <deepspan_accel/ops.hpp>

#include <cstdint>

extern "C" {

/// Returns the HWIP type string for plugin registration.
const char* deepspan_hwip_type() {
    return "accel";
}

/// Dispatch an accel opcode.
/// @param opcode  Raw opcode value (matches AccelOp enum)
/// @param arg0    Command argument 0 (from CMD_ARG0 register)
/// @param arg1    Command argument 1 (from CMD_ARG1 register)
/// @param r0      Output: RESULT_DATA0
/// @param r1      Output: RESULT_DATA1
/// @return 0 on success, non-zero on error
int deepspan_accel_dispatch(uint32_t opcode, uint32_t arg0, uint32_t arg1,
                             uint32_t* r0, uint32_t* r1) {
    using deepspan::accel::AccelOp;

    switch (static_cast<AccelOp>(opcode)) {
        case AccelOp::ECHO:
            *r0 = arg0;
            *r1 = arg1;
            return 0;

        case AccelOp::STATUS:
            *r0 = 0x1u;  // READY
            *r1 = 0u;
            return 0;

        case AccelOp::PROCESS:
            *r0 = 0u;
            *r1 = 0u;
            return 0;

        default:
            *r0 = 0u;
            *r1 = 0u;
            return -1;
    }
}

}  // extern "C"
