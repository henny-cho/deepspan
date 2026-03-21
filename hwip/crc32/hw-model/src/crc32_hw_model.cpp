// SPDX-License-Identifier: Apache-2.0
// crc32_hw_model.cpp — CRC32 HWIP hw-model dispatcher
//
// Implements CRC32 opcode handling for the platform hw-model server.
// The platform hw-model server loads this via set_cmd_handler() lambda
// which also passes the SHM base (for DMA buffer access).
//
// SHM DMA layout (shared with Crc32Plugin):
//   0x000–0x1FF  RegMap (platform registers)
//   0x200–0x21F  ShmStats
//   0x300–0xEFF  DMA data buffer  (kShmDmaOffset, kShmDmaMaxLen=3072)

#include <deepspan_crc32/ops.hpp>

#include <cstdint>
#include <cstring>
#include <mutex>

// SHM layout constants — must match crc32_plugin.cpp
static constexpr uint32_t kShmDmaOffset = 0x300u;

// Global SHM base pointer.
// Set by the hw-model binary or E2E test fixture via
// deepspan_crc32_set_shm_base() before starting the server.
static void* g_shm_base = nullptr;
static std::mutex g_shm_mutex;

extern "C" {

/// Returns the HWIP type string for plugin registration.
const char* deepspan_hwip_type() {
    return "crc32";
}

/// Set the SHM base pointer so the dispatch function can read the DMA buffer.
/// Must be called before the first COMPUTE command is submitted.
void deepspan_crc32_set_shm_base(void* base) {
    std::lock_guard lock{g_shm_mutex};
    g_shm_base = base;
}

/// Compute CRC32 using IEEE 802.3 / Ethernet polynomial (0xEDB88320).
/// Produces the same result as Python binascii.crc32(data) & 0xFFFFFFFF.
static uint32_t compute_crc32(const uint8_t* data, uint32_t len) {
    // Build lookup table on first call (thread-safe via static local init).
    static uint32_t table[256];
    static std::once_flag once;
    std::call_once(once, [] {
        for (uint32_t i = 0; i < 256u; ++i) {
            uint32_t c = i;
            for (int j = 0; j < 8; ++j)
                c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
    });

    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < len; ++i)
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

/// Dispatch a crc32 opcode.
/// @param opcode  Raw opcode value (matches Crc32Op enum)
/// @param arg0    For COMPUTE: byte count of data in DMA buffer
/// @param arg1    Reserved
/// @param r0      Output: RESULT_DATA0 (checksum or polynomial)
/// @param r1      Output: RESULT_DATA1 (reserved, always 0)
/// @return 0 on success, non-zero on error
int deepspan_crc32_dispatch(uint32_t opcode, uint32_t arg0, uint32_t arg1,
                             uint32_t* r0, uint32_t* r1) {
    using deepspan::crc32::Crc32Op;
    (void)arg1;
    *r0 = 0u;
    *r1 = 0u;

    switch (static_cast<Crc32Op>(opcode)) {
        case Crc32Op::COMPUTE: {
            std::lock_guard lock{g_shm_mutex};
            if (!g_shm_base) return -1;
            uint32_t len = arg0;
            if (len == 0u) {
                // CRC32 of empty = 0x00000000
                *r0 = 0x00000000u;
                return 0;
            }
            const auto* data =
                static_cast<const uint8_t*>(g_shm_base) + kShmDmaOffset;
            *r0 = compute_crc32(data, len);
            return 0;
        }

        case Crc32Op::GET_POLY:
            *r0 = 0xEDB88320u;  // IEEE 802.3 / Ethernet CRC32 polynomial
            return 0;

        default:
            return -1;
    }
}

}  // extern "C"
