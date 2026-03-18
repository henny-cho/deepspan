#pragma once
#include <string>
#include <functional>
#include <cstdint>

namespace deepspan::hw_model {

/// SimTransport: Simulation transport based on POSIX shm + eventfd
///
/// Responsibilities:
///   - Create shared memory at /dev/shm/<name> (register map + data buffer)
///   - Simulate IRQ via eventfd (hw-model -> Zephyr native_sim)
///   - Zephyr mmaps this file and uses it like MMIO
class SimTransport {
public:
    using IrqCallback = std::function<void(uint32_t irq_status)>;

    explicit SimTransport(std::string shm_name);
    ~SimTransport();

    // non-copyable, movable
    SimTransport(const SimTransport&) = delete;
    SimTransport& operator=(const SimTransport&) = delete;
    SimTransport(SimTransport&&) noexcept;
    SimTransport& operator=(SimTransport&&) noexcept;

    /// Create and initialize shared memory
    bool init();

    /// Release shared memory
    void cleanup();

    /// Raise IRQ (eventfd write)
    void raise_irq(uint32_t irq_bits);

    /// Return register map pointer (mmap'd address)
    void* reg_base() const { return reg_base_; }

    /// eventfd file descriptor (passed to Zephyr)
    int irq_fd() const { return irq_fd_; }

    /// shm file descriptor
    int shm_fd() const { return shm_fd_; }

    const std::string& shm_name() const { return shm_name_; }

private:
    std::string shm_name_;
    int         shm_fd_  = -1;
    int         irq_fd_  = -1;
    void*       reg_base_ = nullptr;
    size_t      shm_size_ = 0;
};

} // namespace deepspan::hw_model
