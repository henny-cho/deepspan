// SPDX-License-Identifier: Apache-2.0
// test_accel_e2e.cpp — E2E integration tests for the accel HWIP plugin.
//
// Tests run AccelPlugin against an in-process HwModelServer using the
// default SHM name /deepspan_hwip_0.  The server is started before each
// test and torn down afterwards, so there is no dependency on an external
// hw-model process.

#include <gtest/gtest.h>
#include "accel_plugin.hpp"
#include "deepspan/hw_model/hw_model_server.hpp"
#include "deepspan/hw_model/reg_map.hpp"
#include <deepspan_accel/ops.hpp>

#include <cstring>
#include <memory>

using deepspan::hw_model::HwModelServer;
using deepspan::hw_model::HwModelConfig;
using deepspan::hwip::accel::AccelPlugin;

namespace {
constexpr const char* kShmName = "/deepspan_hwip_0";

class AccelE2ETest : public ::testing::Test {
protected:
    void SetUp() override {
        // Start an in-process hw-model using the default SHM name.
        HwModelConfig cfg;
        cfg.shm_name   = kShmName;
        cfg.latency_us = 0;
        cfg.auto_irq   = true;

        server_ = std::make_unique<HwModelServer>(cfg);
        ASSERT_TRUE(server_->init()) << "HwModelServer::init() failed";
        server_->run_async();

        // AccelPlugin constructor opens the SHM (retries up to 5 s).
        plugin_ = std::make_unique<AccelPlugin>("accel/0");
    }

    void TearDown() override {
        plugin_.reset();   // munmap + close fd
        server_->stop();   // stop poll thread + munmap + shm_unlink
        server_.reset();
    }

    std::unique_ptr<HwModelServer> server_;
    std::unique_ptr<AccelPlugin>   plugin_;
};
}  // namespace

/// ECHO opcode: arg0 and arg1 must be echoed back unchanged.
TEST_F(AccelE2ETest, SubmitEcho) {
    constexpr uint32_t kArg0 = 0xDEADBEEFu;
    constexpr uint32_t kArg1 = 0xCAFEBABEu;

    std::vector<uint8_t> data(8);
    std::memcpy(data.data(),     &kArg0, 4);
    std::memcpy(data.data() + 4, &kArg1, 4);

    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::accel::AccelOp::ECHO), data);

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t r0 = 0, r1 = 0;
    std::memcpy(&r0, result.response_data.data(),     4);
    std::memcpy(&r1, result.response_data.data() + 4, 4);

    EXPECT_EQ(r0, kArg0);
    EXPECT_EQ(r1, kArg1);
}

/// STATUS opcode: hw-model returns READY (0x1) in result_data0.
TEST_F(AccelE2ETest, SubmitStatus) {
    // Use the accel hw-model dispatch for STATUS.
    server_->set_cmd_handler(
        [](uint32_t opcode, uint32_t /*arg0*/, uint32_t /*arg1*/,
           uint32_t* r0, uint32_t* r1) -> uint32_t {
            if (static_cast<deepspan::accel::AccelOp>(opcode) ==
                deepspan::accel::AccelOp::STATUS) {
                *r0 = 0x1u;  // READY
                *r1 = 0u;
                return 0u;
            }
            *r0 = *r1 = 0u;
            return static_cast<uint32_t>(-1);
        });

    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::accel::AccelOp::STATUS), {});

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t r0 = 0;
    std::memcpy(&r0, result.response_data.data(), 4);
    EXPECT_EQ(r0, 0x1u);  // STATUS_READY
}

/// device_state() must report READY (proto DEVICE_STATE_READY=2) when hw-model is running.
TEST_F(AccelE2ETest, DeviceStateReady) {
    EXPECT_EQ(plugin_->device_state(), 2);
}

/// Multiple sequential submits must all succeed.
TEST_F(AccelE2ETest, SubmitMultipleSequential) {
    for (uint32_t i = 0; i < 5; ++i) {
        std::vector<uint8_t> data(4);
        std::memcpy(data.data(), &i, 4);

        auto result = plugin_->submit(
            static_cast<uint32_t>(deepspan::accel::AccelOp::ECHO), data);

        ASSERT_EQ(result.response_data.size(), 8u);
        uint32_t r0 = 0;
        std::memcpy(&r0, result.response_data.data(), 4);
        EXPECT_EQ(r0, i) << "echo mismatch at iteration " << i;
    }
}
