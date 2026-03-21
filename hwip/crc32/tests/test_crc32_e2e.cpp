// SPDX-License-Identifier: Apache-2.0
// test_crc32_e2e.cpp — E2E integration tests for the crc32 HWIP plugin.
//
// Tests run Crc32Plugin against an in-process HwModelServer using SHM
// /deepspan_hwip_1 (index 1 avoids conflict with accel tests on index 0).
// The server is started before each test and torn down afterwards.

#include <gtest/gtest.h>
#include "crc32_plugin.hpp"
#include "deepspan/hw_model/hw_model_server.hpp"
#include "deepspan/hw_model/reg_map.hpp"
#include <deepspan_crc32/ops.hpp>

#include <cstring>
#include <memory>
#include <vector>

// Symbols provided by deepspan-crc32-hw-model library.
extern "C" {
void deepspan_crc32_set_shm_base(void* base);
int  deepspan_crc32_dispatch(uint32_t opcode, uint32_t arg0, uint32_t arg1,
                              uint32_t* r0, uint32_t* r1);
}

using deepspan::hw_model::HwModelServer;
using deepspan::hw_model::HwModelConfig;
using deepspan::hwip::crc32::Crc32Plugin;

namespace {

constexpr const char* kShmName = "/deepspan_hwip_1";  // index 1, no accel conflict

// ── Software reference CRC32 (IEEE 802.3 / Ethernet) ────────────────────────
// Must produce identical results to the hw-model implementation.
// Equivalent to Python: binascii.crc32(data) & 0xFFFFFFFF
uint32_t sw_crc32(const uint8_t* data, uint32_t len) {
    static uint32_t table[256];
    static bool     ready = false;
    if (!ready) {
        for (uint32_t i = 0; i < 256u; ++i) {
            uint32_t c = i;
            for (int j = 0; j < 8; ++j)
                c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
            table[i] = c;
        }
        ready = true;
    }
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < len; ++i)
        crc = table[(crc ^ data[i]) & 0xFFu] ^ (crc >> 8);
    return crc ^ 0xFFFFFFFFu;
}

// ── Test fixture ─────────────────────────────────────────────────────────────
class Crc32E2ETest : public ::testing::Test {
protected:
    void SetUp() override {
        HwModelConfig cfg;
        cfg.shm_name   = kShmName;
        cfg.latency_us = 0;
        cfg.auto_irq   = true;

        server_ = std::make_unique<HwModelServer>(cfg);
        ASSERT_TRUE(server_->init()) << "HwModelServer::init() failed";

        // Give the dispatch function access to SHM so it can read the DMA buffer.
        deepspan_crc32_set_shm_base(server_->transport().reg_base());

        server_->set_cmd_handler(
            [](uint32_t op, uint32_t a0, uint32_t a1,
               uint32_t* r0, uint32_t* r1) -> uint32_t {
                int rc = deepspan_crc32_dispatch(op, a0, a1, r0, r1);
                return (rc == 0) ? 0u : 1u;
            });

        server_->run_async();

        plugin_ = std::make_unique<Crc32Plugin>("crc32/1");
    }

    void TearDown() override {
        plugin_.reset();
        server_->stop();
        deepspan_crc32_set_shm_base(nullptr);
        server_.reset();
    }

    std::unique_ptr<HwModelServer> server_;
    std::unique_ptr<Crc32Plugin>   plugin_;
};

}  // namespace

// ── Tests ────────────────────────────────────────────────────────────────────

/// Standard test vector: CRC32("123456789") == 0xCBF43926 (ISO 3309 / Ethernet)
TEST_F(Crc32E2ETest, KnownVector_123456789) {
    const std::vector<uint8_t> data{'1','2','3','4','5','6','7','8','9'};

    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::crc32::Crc32Op::COMPUTE), data);

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t checksum = 0u;
    std::memcpy(&checksum, result.response_data.data(), 4u);

    EXPECT_EQ(checksum, 0xCBF43926u)
        << "Standard CRC32 test vector mismatch";
}

/// Arbitrary string: hw-model result must match software reference.
TEST_F(Crc32E2ETest, ComputeMatchesSoftwareReference) {
    const std::string msg = "Hello, deepspan!";
    const std::vector<uint8_t> data(msg.begin(), msg.end());

    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::crc32::Crc32Op::COMPUTE), data);

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t checksum = 0u;
    std::memcpy(&checksum, result.response_data.data(), 4u);

    uint32_t expected = sw_crc32(data.data(), static_cast<uint32_t>(data.size()));
    EXPECT_EQ(checksum, expected)
        << "hw-model CRC32 differs from software reference";
}

/// Empty input: CRC32 of zero bytes == 0x00000000.
TEST_F(Crc32E2ETest, ComputeEmpty) {
    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::crc32::Crc32Op::COMPUTE), {});

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t checksum = 0xDEADBEEFu;
    std::memcpy(&checksum, result.response_data.data(), 4u);

    EXPECT_EQ(checksum, 0x00000000u) << "CRC32 of empty should be 0";
}

/// get_poly must return the IEEE 802.3 polynomial 0xEDB88320.
TEST_F(Crc32E2ETest, GetPolyReturnsIeee8023) {
    auto result = plugin_->submit(
        static_cast<uint32_t>(deepspan::crc32::Crc32Op::GET_POLY), {});

    ASSERT_EQ(result.response_data.size(), 8u);
    uint32_t poly = 0u;
    std::memcpy(&poly, result.response_data.data(), 4u);

    EXPECT_EQ(poly, 0xEDB88320u) << "Wrong polynomial returned";
}

/// device_state() must report READY (proto DEVICE_STATE_READY=2).
TEST_F(Crc32E2ETest, DeviceStateReady) {
    EXPECT_EQ(plugin_->device_state(), 2);
}

/// Multiple sequential computes must all produce correct results.
TEST_F(Crc32E2ETest, MultipleSequentialComputes) {
    const std::vector<std::string> payloads = {
        "alpha", "bravo", "charlie", "delta", "echo"
    };

    for (const auto& s : payloads) {
        const std::vector<uint8_t> data(s.begin(), s.end());

        auto result = plugin_->submit(
            static_cast<uint32_t>(deepspan::crc32::Crc32Op::COMPUTE), data);

        ASSERT_EQ(result.response_data.size(), 8u);
        uint32_t got = 0u;
        std::memcpy(&got, result.response_data.data(), 4u);

        uint32_t want = sw_crc32(data.data(),
                                 static_cast<uint32_t>(data.size()));
        EXPECT_EQ(got, want) << "Mismatch for payload: " << s;
    }
}
