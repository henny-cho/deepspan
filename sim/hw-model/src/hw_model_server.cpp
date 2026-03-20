#include "deepspan/hw_model/hw_model_server.hpp"
#include "deepspan/hw_model/reg_map.hpp"
#include <thread>
#include <chrono>
#include <cstring>
#include <ctime>

namespace deepspan::hw_model {

HwModelServer::HwModelServer(HwModelConfig cfg)
    : cfg_(std::move(cfg))
    , transport_(cfg_.shm_name)
{
    cmd_handler_ = [this](uint32_t op, uint32_t a0, uint32_t a1,
                           uint32_t* r0, uint32_t* r1) {
        return default_handler(op, a0, a1, r0, r1);
    };
}

HwModelServer::~HwModelServer() {
    stop();
}

bool HwModelServer::init() {
    start_time_sec_ = static_cast<uint64_t>(std::time(nullptr));
    if (!transport_.init()) return false;
    // Write start time into ShmStats once
    auto* stats = reinterpret_cast<ShmStats*>(
        static_cast<char*>(transport_.reg_base()) + SHM_STATS_OFFSET);
    __atomic_store_n(&stats->start_time_sec, start_time_sec_, __ATOMIC_RELAXED);
    // Mark device as READY so plugins can read the state before any command.
    auto* reg = static_cast<RegMap*>(transport_.reg_base());
    __atomic_store_n(&reg->status, status_bits::READY, __ATOMIC_RELEASE);
    return true;
}

void HwModelServer::run() {
    running_.store(true);
    poll_loop();
}

void HwModelServer::run_async() {
    running_.store(true);
    poll_thread_ = std::thread([this]{ poll_loop(); });
}

void HwModelServer::stop() {
    running_.store(false);
    if (poll_thread_.joinable()) {
        poll_thread_.join();
    }
}

void HwModelServer::set_cmd_handler(CmdHandler handler) {
    cmd_handler_ = std::move(handler);
}

void HwModelServer::poll_loop() {
    auto* reg = static_cast<RegMap*>(transport_.reg_base());
    if (!reg) return;

    while (running_.load()) {
        // Poll CTRL.START bit
        uint32_t ctrl = __atomic_load_n(&reg->ctrl, __ATOMIC_ACQUIRE);
        if (ctrl & ctrl_bits::START) {
            // Read command
            uint32_t opcode = reg->cmd_opcode;
            uint32_t arg0   = reg->cmd_arg0;
            uint32_t arg1   = reg->cmd_arg1;

            // Artificial latency
            if (cfg_.latency_us > 0) {
                std::this_thread::sleep_for(
                    std::chrono::microseconds(cfg_.latency_us));
            }

            // Process command
            uint32_t r0 = 0, r1 = 0;
            uint32_t status = cmd_handler_(opcode, arg0, arg1, &r0, &r1);

            // Write result
            reg->result_data0   = r0;
            reg->result_data1   = r1;
            reg->result_status  = status;

            // Update ShmStats before raising IRQ so readers see consistent state
            uint64_t count = cmd_count_.fetch_add(1, std::memory_order_relaxed) + 1;
            auto* stats = reinterpret_cast<ShmStats*>(
                static_cast<char*>(transport_.reg_base()) + SHM_STATS_OFFSET);
            __atomic_store_n(&stats->cmd_count,          count,  __ATOMIC_RELEASE);
            __atomic_store_n(&stats->last_opcode,        opcode, __ATOMIC_RELAXED);
            __atomic_store_n(&stats->last_result_status, status, __ATOMIC_RELAXED);

            // Update STATUS and clear START
            __atomic_and_fetch(&reg->ctrl, ~ctrl_bits::START, __ATOMIC_RELEASE);
            reg->status = status_bits::READY;

            // Raise IRQ
            if (cfg_.auto_irq) {
                transport_.raise_irq(1u);
            }
        }
        std::this_thread::sleep_for(std::chrono::microseconds(100));
    }
}

uint32_t HwModelServer::default_handler(
    uint32_t opcode, uint32_t arg0, uint32_t arg1,
    uint32_t* r0, uint32_t* r1)
{
    // Default handler: echo (returns arg0, arg1 as-is in result)
    (void)opcode;
    *r0 = arg0;
    *r1 = arg1;
    return 0; // success
}

} // namespace deepspan::hw_model
