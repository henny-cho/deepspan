// SPDX-License-Identifier: Apache-2.0
// Package accelserver provides the acceleration HWIP plugin for deepspan.
// It registers itself with the server's hwip registry via init().
package accelserver

// Accel HWIP opcode constants.
// These match the C definitions in hwip/accel/kernel/deepspan_accel.h.
const (
	OpEcho    uint32 = 0x0001 // Echo arg0/arg1 back as result (latency test)
	OpProcess uint32 = 0x0002 // Run data processing pipeline on payload
	OpStatus  uint32 = 0x0003 // Return device status word in result_data0
)
