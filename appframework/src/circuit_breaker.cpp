// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// circuit_breaker.cpp — Implementation of the CircuitBreaker pattern.

#include <deepspan/appframework/circuit_breaker.hpp>

namespace deepspan::appframework {

CircuitBreaker::CircuitBreaker(Config cfg)
    : cfg_(std::move(cfg))
{}

bool CircuitBreaker::call(std::function<bool()> f) {
    {
        std::unique_lock<std::mutex> lock(mu_);

        if (state_ == State::Open) {
            // Check whether the open duration has elapsed; if so, transition
            // to HalfOpen and let exactly one probe through.
            const auto now = std::chrono::steady_clock::now();
            const auto elapsed = now - opened_at_;
            if (elapsed >= cfg_.open_duration) {
                state_ = State::HalfOpen;
                failure_count_ = 0;
                // Fall through: allow the probe call.
            } else {
                // Still open — reject immediately.
                return false;
            }
        }
        // State is Closed or HalfOpen — allow the call.
    }

    const bool ok = f();

    {
        std::unique_lock<std::mutex> lock(mu_);
        if (ok) {
            record_success();
        } else {
            record_failure();
        }
    }

    return ok;
}

CircuitBreaker::State CircuitBreaker::state() const noexcept {
    std::unique_lock<std::mutex> lock(mu_);
    return state_;
}

uint32_t CircuitBreaker::failure_count() const noexcept {
    std::unique_lock<std::mutex> lock(mu_);
    return failure_count_;
}

void CircuitBreaker::reset() {
    std::unique_lock<std::mutex> lock(mu_);
    state_ = State::Closed;
    failure_count_ = 0;
    success_count_ = 0;
    opened_at_ = {};
}

// Called with mu_ held.
void CircuitBreaker::record_success() {
    if (state_ == State::HalfOpen) {
        ++success_count_;
        if (success_count_ >= cfg_.success_threshold) {
            state_ = State::Closed;
            failure_count_ = 0;
            success_count_ = 0;
        }
    } else {
        // In Closed state, a success resets the consecutive failure counter.
        failure_count_ = 0;
        success_count_ = 0;
    }
}

// Called with mu_ held.
void CircuitBreaker::record_failure() {
    ++failure_count_;
    success_count_ = 0;

    if (failure_count_ >= cfg_.failure_threshold) {
        state_ = State::Open;
        opened_at_ = std::chrono::steady_clock::now();
    }
}

} // namespace deepspan::appframework
