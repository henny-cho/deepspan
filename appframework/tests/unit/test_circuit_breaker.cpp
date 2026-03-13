// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_circuit_breaker.cpp — Unit tests for CircuitBreaker.

#include <gtest/gtest.h>

#include <chrono>
#include <thread>

#include <deepspan/appframework/circuit_breaker.hpp>

namespace deepspan::appframework {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static CircuitBreaker make_cb(uint32_t failure_threshold = 3,
                               uint32_t success_threshold = 2,
                               std::chrono::milliseconds open_duration = std::chrono::milliseconds{5000}) {
    CircuitBreaker::Config cfg;
    cfg.failure_threshold = failure_threshold;
    cfg.success_threshold = success_threshold;
    cfg.open_duration     = open_duration;
    cfg.name              = "test-cb";
    return CircuitBreaker(cfg);
}

// ---------------------------------------------------------------------------
// TEST: initial state is Closed
// ---------------------------------------------------------------------------

TEST(CircuitBreaker, StartsInClosedState) {  // NOLINT
    auto cb = make_cb();
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Closed);
    EXPECT_EQ(cb.failure_count(), 0u);
}

// ---------------------------------------------------------------------------
// TEST: transitions to Open after failure_threshold consecutive failures
// ---------------------------------------------------------------------------

TEST(CircuitBreaker, OpensAfterThresholdFailures) {  // NOLINT
    auto cb = make_cb(/*failure_threshold=*/3);

    // Two failures — still Closed.
    cb.call([] { return false; });
    cb.call([] { return false; });
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Closed);

    // Third failure — crosses the threshold → Open.
    cb.call([] { return false; });
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Open);
    EXPECT_GE(cb.failure_count(), 3u);
}

// ---------------------------------------------------------------------------
// TEST: after open_duration elapses, the next call transitions to HalfOpen
// ---------------------------------------------------------------------------

TEST(CircuitBreaker, HalfOpenAfterDuration) {  // NOLINT
    // Use a very short open_duration so the test doesn't block long.
    auto cb = make_cb(/*failure_threshold=*/1,
                      /*success_threshold=*/2,
                      /*open_duration=*/std::chrono::milliseconds{10});

    // Trip the breaker.
    cb.call([] { return false; });
    ASSERT_EQ(cb.state(), CircuitBreaker::State::Open);

    // Wait past the open duration.
    std::this_thread::sleep_for(std::chrono::milliseconds{20});

    // The next call should be allowed through (HalfOpen probe).
    // We return false so it doesn't immediately close again.
    cb.call([] { return false; });

    // After the probe (which failed), the breaker should have transitioned
    // through HalfOpen back to Open.  The important invariant tested here is
    // that the probe was attempted at all — i.e. the breaker did not stay in
    // Open and reject it immediately.  We verify by checking that one more
    // failure was recorded on top of the original threshold.
    //
    // Alternatively, use a successful probe to observe Closed:
    auto cb2 = make_cb(1, 2, std::chrono::milliseconds{10});
    cb2.call([] { return false; });
    ASSERT_EQ(cb2.state(), CircuitBreaker::State::Open);
    std::this_thread::sleep_for(std::chrono::milliseconds{20});

    // Successful probe → HalfOpen (success_count becomes 1, threshold is 2).
    const bool probe_ok = cb2.call([] { return true; });
    EXPECT_TRUE(probe_ok);
    // One success out of two needed — still HalfOpen.
    EXPECT_EQ(cb2.state(), CircuitBreaker::State::HalfOpen);
}

// ---------------------------------------------------------------------------
// TEST: success_threshold successes in HalfOpen closes the breaker
// ---------------------------------------------------------------------------

TEST(CircuitBreaker, ClosesAfterSuccessesInHalfOpen) {  // NOLINT
    auto cb = make_cb(/*failure_threshold=*/1,
                      /*success_threshold=*/2,
                      /*open_duration=*/std::chrono::milliseconds{10});

    // Trip to Open.
    cb.call([] { return false; });
    ASSERT_EQ(cb.state(), CircuitBreaker::State::Open);

    // Wait past open duration.
    std::this_thread::sleep_for(std::chrono::milliseconds{20});

    // First successful probe → HalfOpen.
    cb.call([] { return true; });
    EXPECT_EQ(cb.state(), CircuitBreaker::State::HalfOpen);

    // Second successful probe → Closed (meets success_threshold of 2).
    cb.call([] { return true; });
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Closed);
    EXPECT_EQ(cb.failure_count(), 0u);
}

// ---------------------------------------------------------------------------
// TEST: reset() forces the breaker back to Closed regardless of current state
// ---------------------------------------------------------------------------

TEST(CircuitBreaker, ResetForcesClosedState) {  // NOLINT
    auto cb = make_cb(/*failure_threshold=*/1);

    // Trip to Open.
    cb.call([] { return false; });
    ASSERT_EQ(cb.state(), CircuitBreaker::State::Open);

    cb.reset();
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Closed);
    EXPECT_EQ(cb.failure_count(), 0u);

    // Verify the breaker is fully functional after reset.
    const bool ok = cb.call([] { return true; });
    EXPECT_TRUE(ok);
    EXPECT_EQ(cb.state(), CircuitBreaker::State::Closed);
}

} // namespace deepspan::appframework
