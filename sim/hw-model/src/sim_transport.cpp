#include "deepspan/hw_model/sim_transport.hpp"
#include "deepspan/hw_model/reg_map.hpp"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/eventfd.h>
#include <stdexcept>
#include <cstring>
#include <cerrno>
#include <utility>

namespace deepspan::hw_model {

SimTransport::SimTransport(std::string shm_name)
    : shm_name_(std::move(shm_name)) {}

SimTransport::~SimTransport() {
    cleanup();
}

SimTransport::SimTransport(SimTransport&& o) noexcept
    : shm_name_(std::move(o.shm_name_))
    , shm_fd_(std::exchange(o.shm_fd_, -1))
    , irq_fd_(std::exchange(o.irq_fd_, -1))
    , reg_base_(std::exchange(o.reg_base_, nullptr))
    , shm_size_(std::exchange(o.shm_size_, 0))
{}

bool SimTransport::init() {
    // 1. Create shared memory
    shm_fd_ = shm_open(shm_name_.c_str(),
                       O_CREAT | O_RDWR,
                       S_IRUSR | S_IWUSR);
    if (shm_fd_ < 0) {
        return false;
    }

    shm_size_ = SHM_TOTAL_SIZE;
    if (ftruncate(shm_fd_, static_cast<off_t>(shm_size_)) < 0) {
        return false;
    }

    // 2. mmap
    reg_base_ = mmap(nullptr, shm_size_,
                     PROT_READ | PROT_WRITE,
                     MAP_SHARED, shm_fd_, 0);
    if (reg_base_ == MAP_FAILED) {
        reg_base_ = nullptr;
        return false;
    }

    // 3. Initialize registers
    auto* reg = static_cast<RegMap*>(reg_base_);
    std::memset(reg, 0, sizeof(RegMap));
    reg->version      = HW_VERSION;
    reg->capabilities = HW_CAPS_DMA | HW_CAPS_IRQ | HW_CAPS_MULTI;
    reg->status       = status_bits::READY;

    // 4. eventfd (IRQ simulation)
    irq_fd_ = eventfd(0, EFD_NONBLOCK);
    if (irq_fd_ < 0) {
        return false;
    }

    return true;
}

void SimTransport::cleanup() {
    if (reg_base_ && reg_base_ != MAP_FAILED) {
        munmap(reg_base_, shm_size_);
        reg_base_ = nullptr;
    }
    if (shm_fd_ >= 0) {
        close(shm_fd_);
        shm_unlink(shm_name_.c_str());
        shm_fd_ = -1;
    }
    if (irq_fd_ >= 0) {
        close(irq_fd_);
        irq_fd_ = -1;
    }
}

void SimTransport::raise_irq(uint32_t irq_bits) {
    auto* reg = static_cast<RegMap*>(reg_base_);
    if (reg) {
        __atomic_or_fetch(&reg->irq_status, irq_bits, __ATOMIC_SEQ_CST);
    }
    if (irq_fd_ >= 0) {
        uint64_t val = 1;
        (void)write(irq_fd_, &val, sizeof(val));
    }
}

} // namespace deepspan::hw_model
