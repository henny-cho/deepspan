/**
 * @file main.cpp
 * @brief Deepspan firmware entry point
 *
 * Components are connected at compile time via the CIB nexus.
 * Services start zero-cost with no runtime registration.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/version.h>

#if CONFIG_DEEPSPAN_TRANSPORT_VIRTIO
#include "deepspan/transport/virtio_transport.hpp"
#endif

#if CONFIG_DEEPSPAN_HWIP_DRIVER_SIM
#include "deepspan_hwip.h"

/* Generated opcode constants for the CRC32 HWIP */
#define CRC32_OP_COMPUTE  0x01U   /* dma_bytes: compute CRC32(data) → checksum */
#define CRC32_OP_GET_POLY 0x02U   /* fixed_args: return polynomial 0xEDB88320  */
#endif

LOG_MODULE_REGISTER(deepspan_main, CONFIG_DEEPSPAN_LOG_LEVEL);

int main(void)
{
    LOG_INF("Deepspan firmware starting (Zephyr %s)", KERNEL_VERSION_STRING);

#if CONFIG_DEEPSPAN_TRANSPORT_VIRTIO
    /* TODO: CIB nexus initialization (automatic component wiring)
     * cib::nexus<AppConfig>::init(); */

    static deepspan::transport::DefaultTransport g_transport;
    /* TODO: g_transport.init(SHM_BASE, SHM_SIZE); */

    LOG_INF("Deepspan firmware ready (VirtIO transport)");

    while (true) {
        g_transport.poll();
        k_sleep(K_MSEC(1));
    }

#elif CONFIG_DEEPSPAN_HWIP_DRIVER_SIM
    LOG_INF("Deepspan CRC32 firmware ready (HWIP sim driver)");

    const struct device *hwip = deepspan_hwip_sim_device();

    if (!device_is_ready(hwip)) {
        LOG_ERR("HWIP sim device not ready — is hw-model running?");
        return -1;
    }

    LOG_INF("HWIP hw_version=0x%08x", deepspan_hwip_version(hwip));

    /* ── Test 1: GET_POLY — verify polynomial via fixed_args opcode ─────── */
    {
        uint32_t result_status = 0u;
        uint32_t poly = 0u;
        uint32_t unused = 0u;

        int ret = deepspan_hwip_submit_cmd(
            hwip,
            CRC32_OP_GET_POLY,
            /*arg0=*/0u, /*arg1=*/0u,
            /*timeout_ms=*/3000u,
            &result_status, &poly, &unused
        );

        if (ret == 0) {
            LOG_INF("GET_POLY ok  polynomial=0x%08x  (expected 0xEDB88320)",
                    poly);
            if (poly != 0xEDB88320u) {
                LOG_ERR("Polynomial mismatch — hw-model may not be a CRC32 type");
            }
        } else {
            LOG_ERR("GET_POLY failed: %d", ret);
        }
    }

    /* ── Test 2: COMPUTE — CRC32 of a known string via dma_bytes opcode ─── */
    {
        /* Standard CRC32 test vector: CRC32("123456789") == 0xCBF43926 */
        static const char test_data[] = "123456789";
        const uint32_t test_len = sizeof(test_data) - 1u; /* exclude NUL */

        int dma_ret = deepspan_hwip_set_dma(hwip, test_data, test_len);
        if (dma_ret != 0) {
            LOG_ERR("set_dma failed: %d", dma_ret);
        } else {
            uint32_t result_status = 0u;
            uint32_t checksum = 0u;
            uint32_t unused = 0u;

            int ret = deepspan_hwip_submit_cmd(
                hwip,
                CRC32_OP_COMPUTE,
                /*arg0=*/test_len, /*arg1=*/0u,
                /*timeout_ms=*/3000u,
                &result_status, &checksum, &unused
            );

            if (ret == 0) {
                LOG_INF("COMPUTE ok  CRC32(\"123456789\")=0x%08x"
                        "  (expected 0xCBF43926)  %s",
                        checksum,
                        (checksum == 0xCBF43926u) ? "PASS" : "FAIL");
            } else {
                LOG_ERR("COMPUTE failed: %d", ret);
            }
        }
    }

    /* ── Periodic loop: recompute CRC32 of a rolling message ────────────── */
    {
        static const char loop_data[] = "Hello, deepspan CRC32!";
        const uint32_t loop_len = sizeof(loop_data) - 1u;
        uint32_t seq = 0u;

        while (true) {
            int dma_ret = deepspan_hwip_set_dma(hwip, loop_data, loop_len);
            if (dma_ret == 0) {
                uint32_t result_status = 0u;
                uint32_t checksum = 0u;
                uint32_t unused = 0u;

                int ret = deepspan_hwip_submit_cmd(
                    hwip,
                    CRC32_OP_COMPUTE,
                    loop_len, 0u,
                    3000u,
                    &result_status, &checksum, &unused
                );

                if (ret == 0) {
                    LOG_INF("CRC32 #%u: 0x%08x", seq, checksum);
                } else {
                    LOG_WRN("CRC32 #%u: submit failed %d", seq, ret);
                }
            } else {
                LOG_WRN("CRC32 #%u: set_dma failed %d", seq, dma_ret);
            }

            seq++;
            k_sleep(K_MSEC(2000));
        }
    }

#else
    LOG_INF("Deepspan firmware ready (simulation mode — no transport)");

    while (true) {
        k_sleep(K_MSEC(100));
    }
#endif

    return 0;
}
