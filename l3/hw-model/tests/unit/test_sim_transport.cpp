#include <gtest/gtest.h>
#include "deepspan/hw_model/sim_transport.hpp"
#include "deepspan/hw_model/reg_map.hpp"
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>

using namespace deepspan::hw_model;

class SimTransportTest : public ::testing::Test {
protected:
    static constexpr const char* kShmName = "/deepspan_test_transport";

    void TearDown() override {
        shm_unlink(kShmName);  // cleanup residual
    }
};

TEST_F(SimTransportTest, InitAndCleanup) {
    SimTransport t(kShmName);
    ASSERT_TRUE(t.init());
    EXPECT_GE(t.shm_fd(), 0);
    EXPECT_GE(t.irq_fd(), 0);
    EXPECT_NE(t.reg_base(), nullptr);
}

TEST_F(SimTransportTest, RegistersInitializedCorrectly) {
    SimTransport t(kShmName);
    ASSERT_TRUE(t.init());

    auto* reg = static_cast<RegMap*>(t.reg_base());
    EXPECT_EQ(reg->version, HW_VERSION);
    EXPECT_EQ(reg->status,  status_bits::READY);
    EXPECT_EQ(reg->ctrl,    0u);
    EXPECT_EQ(reg->irq_status, 0u);
}

TEST_F(SimTransportTest, RaiseIrq) {
    SimTransport t(kShmName);
    ASSERT_TRUE(t.init());

    t.raise_irq(0x3u);

    auto* reg = static_cast<RegMap*>(t.reg_base());
    EXPECT_EQ(reg->irq_status & 0x3u, 0x3u);
}

TEST_F(SimTransportTest, ShmNameAccessible) {
    SimTransport t(kShmName);
    ASSERT_TRUE(t.init());
    EXPECT_EQ(t.shm_name(), kShmName);
}
