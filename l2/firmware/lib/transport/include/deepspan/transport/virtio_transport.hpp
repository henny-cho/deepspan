#pragma once

/**
 * @file virtio_transport.hpp
 * @brief VirtioTransport: compile-time parameterized virtio transport
 *
 * Acts as the virtio slave (device) role within Zephyr.
 * Linux userspace mgmt-daemon acts as the virtio master (driver).
 *
 * Shared memory layout:
 *   [0x0000 - 0x3FFF] vring #0 TX (Zephyr -> Linux) 16KB
 *   [0x4000 - 0x7FFF] vring #1 RX (Linux -> Zephyr) 16KB
 *   [0x8000 - 0xFFFF] resource table + config        32KB
 *
 * @tparam TxQueueDepth TX virtqueue depth (default: 16)
 * @tparam RxQueueDepth RX virtqueue depth (default: 16)
 * @tparam BufSize      Buffer size (default: 512)
 */

#include <zephyr/kernel.h>
#include <openamp/open_amp.h>
#include <etl/delegate.h>
#include <etl/expected.h>
#include <cstdint>
#include <cstddef>

namespace deepspan::transport {

/// Transport error codes
enum class TransportError : uint8_t {
    Ok = 0,
    NotInitialized,
    BufferFull,
    SendFailed,
    InvalidChannel,
    Timeout,
};

/// RPMsg receive callback type (ETL delegate — no heap allocation)
using RxCallback = etl::delegate<void(const void* data, size_t len)>;

/**
 * @brief VirtioTransport compile-time configuration struct
 */
template<uint32_t TxQ = 16, uint32_t RxQ = 16, uint32_t BufSz = 512>
struct VirtioConfig {
    static constexpr uint32_t tx_queue_depth = TxQ;
    static constexpr uint32_t rx_queue_depth = RxQ;
    static constexpr uint32_t buf_size       = BufSz;
    static constexpr size_t   vring_size     = 0x4000u; // 16KB per vring
    static constexpr size_t   total_shm_size = 0x10000u; // 64KB
};

/**
 * @brief VirtioTransport: virtio/RPMsg transport (Zephyr slave side)
 *
 * Registered as a CIB component with dependencies wired at compile time.
 *
 * @tparam Cfg VirtioConfig instance
 */
template<typename Cfg = VirtioConfig<>>
class VirtioTransport {
public:
    /// Channel handle
    struct Channel {
        const char*  name;
        uint32_t     dest_addr;
        RxCallback   rx_cb;
    };

    /// Initialization (called from Zephyr SYS_INIT or CIB flow::service)
    bool init(uintptr_t shm_base, size_t shm_size, int notify_fd = -1);

    /// Register an RPMsg channel
    bool register_channel(Channel& ch);

    /// Send data
    etl::expected<size_t, TransportError>
    send(const Channel& ch, const void* data, size_t len);

    /// Receive processing (called from IRQ handler or workqueue)
    void poll();

    bool is_ready() const { return ready_; }

private:
    struct virtio_device  vdev_{};
    struct rpmsg_virtio_device rvdev_{};
    bool ready_ = false;

    // ETL static pool: no heap allocation
    alignas(64) uint8_t tx_pool_[Cfg::tx_queue_depth * Cfg::buf_size];
    alignas(64) uint8_t rx_pool_[Cfg::rx_queue_depth * Cfg::buf_size];
};

/// Default instance type (can be overridden by the application)
using DefaultTransport = VirtioTransport<VirtioConfig<16, 16, 512>>;

} // namespace deepspan::transport
