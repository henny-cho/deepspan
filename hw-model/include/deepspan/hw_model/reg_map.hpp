#pragma once
#include <cstdint>
#include <cstddef>

namespace deepspan::hw_model {

/// HWIP register map offsets (same offsets as real HW)
/// Must match the reg property offsets in the Zephyr DTS.
struct RegMap {
    // Control registers (offset 0x000 - 0x0FF)
    volatile uint32_t ctrl;          ///< 0x000: Control register
    volatile uint32_t status;        ///< 0x004: Status register (read-only)
    volatile uint32_t irq_status;    ///< 0x008: IRQ status (write-1-to-clear)
    volatile uint32_t irq_enable;    ///< 0x00C: IRQ enable mask
    volatile uint32_t version;       ///< 0x010: HW version (read-only)
    volatile uint32_t capabilities;  ///< 0x014: Feature bits (read-only)
    volatile uint32_t _reserved0[58];

    // Data registers (offset 0x100 - 0x1FF)
    volatile uint32_t cmd_opcode;    ///< 0x100: Command opcode
    volatile uint32_t cmd_arg0;      ///< 0x104: Command argument 0
    volatile uint32_t cmd_arg1;      ///< 0x108: Command argument 1
    volatile uint32_t cmd_flags;     ///< 0x10C: Command flags
    volatile uint32_t result_status; ///< 0x110: Result status
    volatile uint32_t result_data0;  ///< 0x114: Result data 0
    volatile uint32_t result_data1;  ///< 0x118: Result data 1
    volatile uint32_t _reserved1[57];
};
static_assert(offsetof(RegMap, cmd_opcode) == 0x100);
static_assert(sizeof(RegMap) == 0x200);

/// CTRL register bit definitions
namespace ctrl_bits {
    constexpr uint32_t RESET    = (1u << 0);  ///< Soft reset
    constexpr uint32_t START    = (1u << 1);  ///< Start command
    constexpr uint32_t IRQ_CLR  = (1u << 2);  ///< Clear IRQ
}

/// STATUS register bit definitions
namespace status_bits {
    constexpr uint32_t READY    = (1u << 0);  ///< Device ready
    constexpr uint32_t BUSY     = (1u << 1);  ///< Processing
    constexpr uint32_t ERROR    = (1u << 2);  ///< Error occurred
}

/// HW version and capability constants
constexpr uint32_t HW_VERSION     = 0x0001'0000u;  ///< v1.0.0
constexpr uint32_t HW_CAPS_DMA    = (1u << 0);
constexpr uint32_t HW_CAPS_IRQ    = (1u << 1);
constexpr uint32_t HW_CAPS_MULTI  = (1u << 2);     ///< Multi-device support

/// Shared memory layout
constexpr size_t SHM_REG_SIZE   = sizeof(RegMap);  ///< Register region
constexpr size_t SHM_TOTAL_SIZE = 4096u;            ///< Total shm size (page-aligned)

} // namespace deepspan::hw_model
