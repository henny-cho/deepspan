// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_device_integration.cpp — Integration tests for DeepspanDevice.
//
// These tests require a real /dev/hwip0 device (or simulation via hw-model).
// Every test calls GTEST_SKIP() when the device is unavailable so that the
// standard CI build (no hardware) still reports a clean result.

#include <gtest/gtest.h>

#include <fcntl.h>
#include <unistd.h>

#include "deepspan/userlib/async_client.hpp"
#include "deepspan/userlib/device.hpp"
#include "deepspan/userlib/error.hpp"

#include <linux/deepspan.h>
#include <linux/deepspan_accel.h>  // DEEPSPAN_ACCEL_OP_*

namespace deepspan::userlib {

// Helper: returns true when /dev/hwip0 is accessible.
static bool hw_available() noexcept {
    return ::access("/dev/hwip0", F_OK | R_OK | W_OK) == 0;
}

// ---------------------------------------------------------------------------
// DeepspanDevice integration: open real device
// ---------------------------------------------------------------------------

TEST(DeepspanDeviceIntegration, OpenHwip0) {
    if (!hw_available()) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping hardware test";
    }
    auto result = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(result.has_value()) << "open failed: "
        << static_cast<int>(result.error());
    EXPECT_GE(result->fd(), 0);
}

TEST(DeepspanDeviceIntegration, UapiVersionMatch) {
    if (!hw_available()) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping hardware test";
    }
    auto result = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(result.has_value());
    // The kernel driver must expose the same UAPI version the library was built against.
    EXPECT_GE(result->kernel_uapi_version(), DEEPSPAN_UAPI_VERSION_MIN);
}

// ---------------------------------------------------------------------------
// AsyncClient integration: create ring on real device
// ---------------------------------------------------------------------------

TEST(AsyncClientIntegration, CreateAndDestroy) {
    if (!hw_available()) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping hardware test";
    }
    auto dev = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(dev.has_value());

    auto client = AsyncClient::create(*dev, /*queue_depth=*/16);
    ASSERT_TRUE(client.has_value()) << "AsyncClient::create failed: "
        << static_cast<int>(client.error());
    // Destruction should release io_uring resources without crashing.
}

TEST(AsyncClientIntegration, SubmitNoopAndWait) {
    if (!hw_available()) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping hardware test";
    }
    auto dev = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(dev.has_value());

    auto client = AsyncClient::create(*dev);
    ASSERT_TRUE(client.has_value());

    // Send an ECHO (opcode 1) and wait for the completion.
    deepspan_req req{};
    req.opcode = DEEPSPAN_ACCEL_OP_ECHO;

    auto result = client->submit_and_wait(req);
    ASSERT_TRUE(result.has_value()) << "submit_and_wait failed: "
        << static_cast<int>(result.error());
    EXPECT_EQ(result->status, 0);
}

} // namespace deepspan::userlib
