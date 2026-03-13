// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// session_manager.hpp — Session lifecycle management combining DevicePool + CircuitBreaker.
#pragma once
#include "device_pool.hpp"
#include "circuit_breaker.hpp"
#include <deepspan/userlib/error.hpp>
#include <etl/expected.h>
#include <cstdint>
#include <functional>
#include <memory>
#include <vector>

namespace deepspan::appframework {

// SessionManager: top-level session manager connecting DevicePool and CircuitBreaker
// Maintains a CircuitBreaker per device path; blocks the device on consecutive failures.
class SessionManager {
public:
    struct Config {
        std::vector<std::string> device_paths;
        unsigned uring_queue_depth{64};
        CircuitBreaker::Config cb_config{};
    };

    static etl::expected<SessionManager, deepspan::userlib::Error> create(Config cfg);

    // execute(): executes f using an available device.
    // f: (AsyncClient&) → bool  (true=success, false=failure for CB)
    etl::expected<void, deepspan::userlib::Error>
        execute(std::function<bool(deepspan::userlib::AsyncClient&)> f);

    CircuitBreaker::State circuit_state() const noexcept;

    // Non-copyable (DevicePool is non-copyable).
    SessionManager(const SessionManager&) = delete;
    SessionManager& operator=(const SessionManager&) = delete;

    // Movable.
    SessionManager(SessionManager&&) noexcept = default;
    SessionManager& operator=(SessionManager&&) noexcept = default;

private:
    explicit SessionManager(std::unique_ptr<DevicePool> pool, CircuitBreaker cb);
    std::unique_ptr<DevicePool> pool_;
    CircuitBreaker cb_;
};

} // namespace deepspan::appframework
