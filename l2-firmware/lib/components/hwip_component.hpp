#pragma once

/**
 * @file hwip_component.hpp
 * @brief CIB component: HWIP driver interface
 *
 * Components are connected at compile time via cib::extend with no runtime overhead.
 *
 * Usage example:
 * @code
 * // nexus definition (app/src/config.hpp)
 * constexpr auto config = cib::config(
 *     cib::extend<HwipService>(HwipComponent{})
 * );
 * @endcode
 */

#include <cib/cib.hpp>
#include <etl/fsm.h>
#include <etl/delegate.h>
#include <cstdint>

namespace deepspan::components {

/// HWIP event IDs (for ETL FSM)
enum class HwipEventId : uint32_t {
    Init = 0,
    CmdReceived,
    CmdComplete,
    Error,
    Reset,
};

/// HWIP FSM state IDs
enum class HwipStateId : uint32_t {
    Uninitialized = 0,
    Initializing,
    Ready,
    Processing,
    Error,
};

/// HWIP command event (ETL message)
struct CmdEvent : public etl::message<static_cast<etl::message_id_t>(HwipEventId::CmdReceived)> {
    uint32_t opcode;
    uint32_t arg0;
    uint32_t arg1;
};

/// HWIP completion event
struct CompleteEvent : public etl::message<static_cast<etl::message_id_t>(HwipEventId::CmdComplete)> {
    uint32_t status;
    uint32_t result0;
    uint32_t result1;
};

/**
 * @brief HwipComponent: HWIP driver CIB component
 *
 * Manages state with an ETL FSM and guarantees initialization order via CIB flow::service.
 */
class HwipComponent {
public:
    /// CIB service interface (for flow::service wiring)
    void start();
    void stop();

    /// Command handling (ISR context or workqueue)
    void handle_cmd(const CmdEvent& ev);

    bool is_ready() const { return state_ == HwipStateId::Ready; }

private:
    HwipStateId state_ = HwipStateId::Uninitialized;
};

} // namespace deepspan::components
