#pragma once
#include "reg_map.hpp"
#include "sim_transport.hpp"
#include <atomic>
#include <thread>
#include <functional>
#include <string>
#include <cstdint>

namespace deepspan::hw_model {

struct HwModelConfig {
    std::string shm_name    = "/deepspan_hwip_0";
    uint32_t    latency_us  = 0;      ///< Artificial response latency (for testing)
    bool        auto_irq    = true;   ///< Automatically raise IRQ on command completion
};

/// HwModelServer: Software simulation of HWIP hardware behavior
///
/// Operation flow:
///   1. Zephyr sets the CTRL.START bit
///   2. HwModelServer reads the CMD register
///   3. Command processing (echo or custom handler)
///   4. Write result to RESULT register
///   5. Raise IRQ (eventfd)
///   6. Zephyr ISR reads the result
class HwModelServer {
public:
    using CmdHandler = std::function<uint32_t(uint32_t opcode,
                                               uint32_t arg0,
                                               uint32_t arg1,
                                               uint32_t* result0,
                                               uint32_t* result1)>;

    explicit HwModelServer(HwModelConfig cfg = {});
    ~HwModelServer();

    /// Initialize (create shm, initialize registers)
    bool init();

    /// Start event loop (blocking)
    void run();

    /// Run in background thread
    void run_async();

    /// Stop
    void stop();

    /// Register a custom command handler (default: echo)
    void set_cmd_handler(CmdHandler handler);

    SimTransport& transport() { return transport_; }

private:
    void poll_loop();
    uint32_t default_handler(uint32_t opcode, uint32_t arg0, uint32_t arg1,
                             uint32_t* r0, uint32_t* r1);

    HwModelConfig    cfg_;
    SimTransport     transport_;
    CmdHandler       cmd_handler_;
    std::atomic_bool running_{false};
    std::thread      poll_thread_;
    std::atomic<uint64_t> cmd_count_{0};
    uint64_t         start_time_sec_{0};
};

} // namespace deepspan::hw_model
