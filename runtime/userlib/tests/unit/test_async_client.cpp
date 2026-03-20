// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024 Deepspan Project Authors
//
// test_async_client.cpp — Unit tests for AsyncClient.

#include <gtest/gtest.h>

#include <unistd.h>  // access()

#include "deepspan/userlib/async_client.hpp"
#include "deepspan/userlib/device.hpp"
#include "deepspan/userlib/error.hpp"

// UAPI types and opcode constants.
#include <linux/deepspan.h>        // NOLINT(hicpp-deprecated-headers)
#include <linux/deepspan_accel.h>  // DEEPSPAN_ACCEL_OP_*

namespace deepspan::userlib {

// ---------------------------------------------------------------------------
// Helper: a DeepspanDevice-like stand-in with an invalid fd, for negative tests.
//
// We cannot construct a DeepspanDevice with fd=-1 directly (the constructor is
// private), so we use a raw trick: open /dev/null and use its fd, then pass it
// through the public open() path for negative testing of AsyncClient, or we
// test via the static factory with a moved-out device.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// TEST: creating an AsyncClient with an invalid device fd fails gracefully
// ---------------------------------------------------------------------------

TEST(AsyncClient, CreateFailsWithoutDevice) {  // NOLINT
    // Strategy: open a valid DeepspanDevice on a real path, then move-assign
    // it so the original is in the moved-from (invalid) state, then try to
    // create an AsyncClient from the invalidated handle.
    //
    // If no real device is present we manufacture an invalid device by opening
    // a non-existent path (which fails) and attempting AsyncClient::create with
    // a local DeepspanDevice whose fd stays at -1 via the no-device path.
    //
    // Since DeepspanDevice's constructor is private, we rely on AsyncClient::create
    // checking device.fd() < 0 and returning an appropriate error.

    // We need a DeepspanDevice with fd==-1.  The only way to get one without a
    // real device is to produce a moved-from instance.
    //
    // Attempt to open a nonexistent device to get a failed expected; then open
    // a valid one and move it so the source is invalid.

    if (::access("/dev/hwip0", F_OK) != 0) {
        // No device available.  We cannot get a DeepspanDevice instance at all,
        // so we verify the error path indirectly via the DeviceOpenFailed path.
        auto dev_result = DeepspanDevice::open("/dev/hwip0");
        ASSERT_FALSE(dev_result.has_value());
        // We can't call AsyncClient::create without a DeepspanDevice object.
        // This test verifies the device-open path rejects bad paths.
        EXPECT_EQ(dev_result.error(), Error::DeviceOpenFailed);
        return;
    }

    // We have a real device.  Open it, move-from it, then pass the moved-from
    // handle to AsyncClient::create.
    auto dev_result = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(dev_result.has_value());

    // Move the device out — dev_result->fd() becomes -1.
    DeepspanDevice dev{std::move(*dev_result)};
    // Now move *that* away so 'dev' itself becomes invalid.
    DeepspanDevice dev2{std::move(dev)};

    // 'dev' is now moved-from with fd==-1.
    ASSERT_EQ(dev.fd(), -1);  // NOLINT(bugprone-use-after-move)

    auto client_result = AsyncClient::create(dev);  // NOLINT(bugprone-use-after-move)
    ASSERT_FALSE(client_result.has_value());
    EXPECT_TRUE(client_result.error() == Error::IouringSetupFailed ||
                client_result.error() == Error::DeviceOpenFailed)
        << "Expected IouringSetupFailed or DeviceOpenFailed, got: "
        << to_string(client_result.error());
}

// ---------------------------------------------------------------------------
// TEST: submit DEEPSPAN_ACCEL_OP_ECHO on a real device and verify status == 0
// ---------------------------------------------------------------------------

TEST(AsyncClient, SubmitAndWaitOnRealDevice) {  // NOLINT
    if (::access("/dev/hwip0", F_OK) != 0) {
        GTEST_SKIP() << "/dev/hwip0 not available; skipping real-device test";
    }

    auto dev_result = DeepspanDevice::open("/dev/hwip0");
    ASSERT_TRUE(dev_result.has_value())
        << "DeepspanDevice::open failed: " << to_string(dev_result.error());

    auto client_result = AsyncClient::create(*dev_result);
    ASSERT_TRUE(client_result.has_value())
        << "AsyncClient::create failed: " << to_string(client_result.error());

    deepspan_req req{};
    req.opcode     = DEEPSPAN_ACCEL_OP_ECHO;
    req.flags      = 0;
    req.data_ptr   = 0;
    req.data_len   = 0;
    req.timeout_ms = 1000;  // 1 second timeout

    auto result = client_result->submit_and_wait(req);
    ASSERT_TRUE(result.has_value())
        << "submit_and_wait failed: " << to_string(result.error());

    EXPECT_EQ(result->status, 0)
        << "ECHO operation returned non-zero status: " << result->status;
}

} // namespace deepspan::userlib
