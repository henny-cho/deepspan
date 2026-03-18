#include "deepspan/transport/virtio_transport.hpp"
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(deepspan_transport, CONFIG_DEEPSPAN_LOG_LEVEL);

namespace deepspan::transport {

template<typename Cfg>
bool VirtioTransport<Cfg>::init(uintptr_t shm_base, size_t shm_size, int notify_fd)
{
    (void)notify_fd;
    if (shm_size < Cfg::total_shm_size) {
        LOG_ERR("shm too small: %zu < %zu", shm_size, Cfg::total_shm_size);
        return false;
    }

    // TODO: set up libmetal io region, initialize vrings
    // Actual implementation is performed in the platform-specific transport backend
    LOG_INF("VirtioTransport init: shm_base=0x%lx, size=%zu",
            (unsigned long)shm_base, shm_size);

    ready_ = true;
    return true;
}

template<typename Cfg>
bool VirtioTransport<Cfg>::register_channel(Channel& ch)
{
    LOG_INF("Registering RPMsg channel: %s", ch.name);
    return true;
}

template<typename Cfg>
etl::expected<size_t, TransportError>
VirtioTransport<Cfg>::send(const Channel& ch, const void* data, size_t len)
{
    if (!ready_) {
        return etl::unexpected(TransportError::NotInitialized);
    }
    if (len > Cfg::buf_size) {
        return etl::unexpected(TransportError::BufferFull);
    }
    (void)ch; (void)data;
    // TODO: call rpmsg_send()
    return len;
}

template<typename Cfg>
void VirtioTransport<Cfg>::poll()
{
    // TODO: process virtqueue receive
}

// Explicit instantiation
template class VirtioTransport<VirtioConfig<16, 16, 512>>;

} // namespace deepspan::transport
