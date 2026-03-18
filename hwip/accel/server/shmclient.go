// SPDX-License-Identifier: Apache-2.0
// AccelShmClient: acceleration HWIP command submission via POSIX shm RegMap.
// Protocol: write cmd registers → set CTRL.START → poll until START clears → read result.
package accelserver

import (
	"encoding/binary"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

// Accel RegMap offsets — must match hwip/accel/hw-model/include/deepspan_accel/reg_map.hpp.
const (
	regCtrl         = 0x000
	regCmdOpcode    = 0x100
	regCmdArg0      = 0x104
	regCmdArg1      = 0x108
	regCmdFlags     = 0x10C
	regResultStatus = 0x110
	regResultData0  = 0x114
	regResultData1  = 0x118

	ctrlStart = uint32(1 << 1) // CTRL.START bit

	shmMapSize = 4096
)

// AccelShmClient submits commands to the accel hw-model via POSIX shared memory.
// Safe for concurrent use; an internal mutex serialises commands since the
// hw-model RegMap has no per-slot command queuing.
type AccelShmClient struct {
	mu      sync.Mutex
	shmPath string // empty → stub mode (no real shm)
}

// NewShmClient returns an AccelShmClient.  Pass shmName="" for stub/test mode.
func NewShmClient(shmName string) *AccelShmClient {
	path := ""
	if shmName != "" {
		path = "/dev/shm/" + shmName
	}
	return &AccelShmClient{shmPath: path}
}

// SubmitCmd implements Submitter.
func (c *AccelShmClient) SubmitCmd(opcode, arg0, arg1 uint32, timeoutMs uint32) (status, data0, data1 uint32, err error) {
	if c.shmPath == "" {
		// stub: echo opcode back as data0
		return 0, opcode, 0, nil
	}
	if timeoutMs == 0 {
		timeoutMs = 5000
	}

	c.mu.Lock()
	defer c.mu.Unlock()

	f, err := os.OpenFile(c.shmPath, os.O_RDWR, 0)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("accel shm open: %w", err)
	}
	defer func() { _ = f.Close() }()

	data, err := syscall.Mmap(int(f.Fd()), 0, shmMapSize,
		syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("accel mmap: %w", err)
	}
	defer syscall.Munmap(data) //nolint:errcheck

	le := binary.LittleEndian
	le.PutUint32(data[regCmdOpcode:], opcode)
	le.PutUint32(data[regCmdArg0:], arg0)
	le.PutUint32(data[regCmdArg1:], arg1)
	le.PutUint32(data[regCmdFlags:], 0)

	// Set CTRL.START atomically (CAS loop)
	ctrlPtr := (*uint32)(unsafe.Pointer(&data[regCtrl]))
	for {
		old := atomic.LoadUint32(ctrlPtr)
		if atomic.CompareAndSwapUint32(ctrlPtr, old, old|ctrlStart) {
			break
		}
	}

	// Poll until hw-model clears CTRL.START
	deadline := time.Now().Add(time.Duration(timeoutMs) * time.Millisecond)
	for atomic.LoadUint32(ctrlPtr)&ctrlStart != 0 {
		if time.Now().After(deadline) {
			return 0, 0, 0, fmt.Errorf("accel timeout (%dms) waiting for hw-model", timeoutMs)
		}
		time.Sleep(time.Millisecond)
	}

	status = le.Uint32(data[regResultStatus:])
	data0 = le.Uint32(data[regResultData0:])
	data1 = le.Uint32(data[regResultData1:])
	return status, data0, data1, nil
}
