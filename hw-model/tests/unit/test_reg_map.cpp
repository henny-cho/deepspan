#include <gtest/gtest.h>
#include "deepspan/hw_model/reg_map.hpp"
#include <cstddef>

using namespace deepspan::hw_model;

TEST(RegMap, OffsetCheck) {
    EXPECT_EQ(offsetof(RegMap, ctrl),         0x000u);
    EXPECT_EQ(offsetof(RegMap, status),       0x004u);
    EXPECT_EQ(offsetof(RegMap, irq_status),   0x008u);
    EXPECT_EQ(offsetof(RegMap, irq_enable),   0x00Cu);
    EXPECT_EQ(offsetof(RegMap, version),      0x010u);
    EXPECT_EQ(offsetof(RegMap, cmd_opcode),   0x100u);
    EXPECT_EQ(offsetof(RegMap, result_status),0x110u);
}

TEST(RegMap, SizeCheck) {
    EXPECT_EQ(sizeof(RegMap), 0x200u);
}

TEST(RegMap, CtrlBits) {
    EXPECT_EQ(ctrl_bits::RESET,   0x1u);
    EXPECT_EQ(ctrl_bits::START,   0x2u);
}

TEST(RegMap, StatusBits) {
    EXPECT_EQ(status_bits::READY, 0x1u);
    EXPECT_EQ(status_bits::BUSY,  0x2u);
    EXPECT_EQ(status_bits::ERROR, 0x4u);
}

TEST(RegMap, ShmTotalSize) {
    EXPECT_GE(SHM_TOTAL_SIZE, sizeof(RegMap));
    EXPECT_EQ(SHM_TOTAL_SIZE % 4096, 0u);  // page-aligned
}
