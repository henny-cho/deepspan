// SPDX-License-Identifier: Apache-2.0
// hw_model_stub.cpp — HW model simulator stub for mychip
//
// Replace with an actual register-level simulation of your hardware.
// See hwip/accel/sim/ for a complete example.
#include <cstdint>

namespace deepspan::hwip::mychip::sim {

// TODO: implement register read/write simulation.
void write_reg(uint32_t offset, uint32_t value) { (void)offset; (void)value; }
uint32_t read_reg(uint32_t offset) { (void)offset; return 0u; }

}  // namespace deepspan::hwip::mychip::sim
