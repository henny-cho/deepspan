// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// circuit_breaker.hpp — CircuitBreaker pattern to prevent cascading failures.
#pragma once
#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>

namespace deepspan::appframework {

// CircuitBreaker: automatically blocks on consecutive failures, auto-recovers to half-open state after a timeout
// States: CLOSED (normal) → OPEN (blocked) → HALF_OPEN (probing) → CLOSED
class CircuitBreaker {
public:
    enum class State { Closed, Open, HalfOpen };

    struct Config {
        uint32_t failure_threshold{5};         // consecutive failure count threshold to enter OPEN
        uint32_t success_threshold{2};          // consecutive success count threshold for HALF_OPEN → CLOSED
        std::chrono::milliseconds open_duration{5000};  // duration to stay in OPEN state
        std::string name;                       // identifier (for logging)
    };

    explicit CircuitBreaker(Config cfg);

    // call(): executes function f. Returns false immediately if in OPEN state.
    // f returns true → records success, false → records failure
    bool call(std::function<bool()> f);

    State state() const noexcept;
    uint32_t failure_count() const noexcept;
    void reset();  // force reset to CLOSED

private:
    void record_success();
    void record_failure();
    bool try_half_open();

    mutable std::mutex mu_;
    Config cfg_;
    State state_{State::Closed};
    uint32_t failure_count_{0};
    uint32_t success_count_{0};
    std::chrono::steady_clock::time_point opened_at_{};
};

} // namespace deepspan::appframework
