// SPDX-License-Identifier: Apache-2.0
package hwip

// Submitter submits a single HWIP command and returns the result.
//
// Implementations:
//   - *ShmClient  — simulation mode: writes directly to hw-model POSIX shm RegMap
//   - *CgoClient  — production mode: routes through SessionManager (DevicePool +
//     CircuitBreaker) using io_uring URING_CMD on /dev/hwipN
type Submitter interface {
	// SubmitCmd issues opcode with arg0/arg1 and blocks until completion.
	// timeoutMs=0 uses the implementation default (typically 5000 ms).
	// Returns (result_status, result_data0, result_data1, error).
	SubmitCmd(opcode, arg0, arg1 uint32, timeoutMs uint32) (status, data0, data1 uint32, err error)
}
