// SPDX-License-Identifier: Apache-2.0
// Package accel implements the deepspan ACCEL HWIP Submitter using POSIX shared
// memory MMIO (simulation) and the kernel /dev/hwipN interface (production).
//
// Usage:
//
//	// Simulation mode (hw-model POSIX shm):
//	c, err := accel.NewShmClient(accel.WithShmName("/deepspan_accel_0"))
//
//	// Stub mode (unit tests, no hardware):
//	c := accel.NewStubClient()
package accel

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"
	"unsafe"

	"golang.org/x/sys/unix"
)

// Register offsets — mirror gen/l4-rpc/deepspan_accel/opcodes.go.
// Kept here to avoid a cross-module import; validated by TestRegisterOffsets.
const (
	regCtrl         uint32 = 0x0000
	regStatus       uint32 = 0x0004
	regCmdOpcode    uint32 = 0x0100
	regCmdArg0      uint32 = 0x0104
	regCmdArg1      uint32 = 0x0108
	regResultStatus uint32 = 0x0110
	regResultData0  uint32 = 0x0114
	regResultData1  uint32 = 0x0118

	regMapSize = 0x200 // total MMIO region size (bytes)
)

// Control / status bit masks.
const (
	ctrlReset uint32 = 1 << 0
	ctrlStart uint32 = 1 << 1

	statusReady uint32 = 1 << 0
	statusBusy  uint32 = 1 << 1
	statusError uint32 = 1 << 2
)

// defaultTimeout is used when timeoutMs == 0.
const defaultTimeoutMs = 5_000

// ── ShmClient ────────────────────────────────────────────────────────────────

// ShmClient implements hwip.Submitter by memory-mapping a POSIX shared memory
// region that the hw-model process exposes as a virtual MMIO register file.
//
// All register accesses are 32-bit little-endian, matching the hw-model layout.
type ShmClient struct {
	mu      sync.Mutex
	shmName string
	version string
	fd      int
	regs    []byte // mmap'd view of regMapSize bytes
}

// Option configures a ShmClient.
type Option func(*ShmClient)

// WithShmName sets the POSIX shm name (e.g. "/deepspan_accel_0").
// Default: "/deepspan_accel_0".
func WithShmName(name string) Option {
	return func(c *ShmClient) { c.shmName = name }
}

// WithVersion sets the version string returned by SubmitterInfo.Version().
func WithVersion(v string) Option {
	return func(c *ShmClient) { c.version = v }
}

// NewShmClient opens the POSIX shm region and returns a ready ShmClient.
func NewShmClient(opts ...Option) (*ShmClient, error) {
	c := &ShmClient{
		shmName: "/deepspan_accel_0",
		version: "1.0.0",
	}
	for _, o := range opts {
		o(c)
	}

	fd, err := unix.Open("/dev/shm"+c.shmName, os.O_RDWR, 0)
	if err != nil {
		// Fallback: shm_open path on Linux
		fd, err = unix.Open("/dev/shm"+c.shmName[1:], os.O_RDWR, 0)
		if err != nil {
			return nil, fmt.Errorf("accel: open shm %q: %w", c.shmName, err)
		}
	}

	regs, err := unix.Mmap(fd, 0, regMapSize, unix.PROT_READ|unix.PROT_WRITE, unix.MAP_SHARED)
	if err != nil {
		unix.Close(fd) //nolint:errcheck
		return nil, fmt.Errorf("accel: mmap shm: %w", err)
	}

	c.fd = fd
	c.regs = regs
	return c, nil
}

// Close releases the mmap and closes the shm file descriptor.
func (c *ShmClient) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	var errs []error
	if c.regs != nil {
		if err := unix.Munmap(c.regs); err != nil {
			errs = append(errs, err)
		}
		c.regs = nil
	}
	if c.fd >= 0 {
		if err := unix.Close(c.fd); err != nil {
			errs = append(errs, err)
		}
		c.fd = -1
	}
	return errors.Join(errs...)
}

// SubmitCmd implements hwip.Submitter.
func (c *ShmClient) SubmitCmd(opcode, arg0, arg1 uint32, timeoutMs uint32) (status, data0, data1 uint32, err error) {
	if timeoutMs == 0 {
		timeoutMs = defaultTimeoutMs
	}
	c.mu.Lock()
	defer c.mu.Unlock()

	// Write command registers.
	c.write32(regCmdOpcode, opcode)
	c.write32(regCmdArg0, arg0)
	c.write32(regCmdArg1, arg1)

	// Assert START bit.
	c.write32(regCtrl, ctrlStart)

	// Poll the CTRL register until hw clears the START bit (= command complete).
	// Using CTRL as completion signal avoids a race where STATUS=READY from the
	// previous command causes an early exit before the hw processes the new one.
	deadline := time.Now().Add(time.Duration(timeoutMs) * time.Millisecond)
	for {
		ctrl := c.read32(regCtrl)
		if ctrl&ctrlStart == 0 {
			break // hw cleared START → command is done
		}
		// Check STATUS for hw-signalled errors mid-flight.
		if c.read32(regStatus)&statusError != 0 {
			c.write32(regCtrl, ctrlReset)
			return 0, 0, 0, fmt.Errorf("accel: hw error (opcode=0x%04x)", opcode)
		}
		if time.Now().After(deadline) {
			c.write32(regCtrl, ctrlReset)
			return 0, 0, 0, fmt.Errorf("accel: command timeout after %dms (opcode=0x%04x)", timeoutMs, opcode)
		}
		time.Sleep(100 * time.Microsecond)
	}

	status = c.read32(regResultStatus)
	data0 = c.read32(regResultData0)
	data1 = c.read32(regResultData1)
	return status, data0, data1, nil
}

// HwipType implements hwip.SubmitterInfo.
func (c *ShmClient) HwipType() string { return "accel" }

// Version implements hwip.SubmitterInfo.
func (c *ShmClient) Version() string { return c.version }

// read32 / write32: little-endian 32-bit MMIO helpers.
func (c *ShmClient) read32(offset uint32) uint32 {
	return binary.LittleEndian.Uint32(c.regs[offset : offset+4])
}

func (c *ShmClient) write32(offset, val uint32) {
	binary.LittleEndian.PutUint32(c.regs[offset:offset+4], val)
}

// Ensure unsafe.Pointer arithmetic is valid (regs is a []byte so index access is fine).
var _ = unsafe.Sizeof(uint32(0)) // keep unsafe import used

// ── StubClient ────────────────────────────────────────────────────────────────

// StubClient is a no-hardware Submitter for unit tests.
// It echoes opcode as data0 and returns zero for all other fields.
type StubClient struct {
	hwipVersion string
}

// NewStubClient returns a StubClient ready for use in tests.
func NewStubClient(opts ...Option) *StubClient {
	s := &StubClient{hwipVersion: "stub-1.0.0"}
	// Apply version option if provided.
	tmp := &ShmClient{}
	for _, o := range opts {
		o(tmp)
	}
	if tmp.version != "" {
		s.hwipVersion = tmp.version
	}
	return s
}

// SubmitCmd implements hwip.Submitter (echo mode).
func (s *StubClient) SubmitCmd(opcode, _, _ uint32, _ uint32) (uint32, uint32, uint32, error) {
	return 0, opcode, 0, nil
}

// HwipType implements hwip.SubmitterInfo.
func (s *StubClient) HwipType() string { return "accel" }

// Version implements hwip.SubmitterInfo.
func (s *StubClient) Version() string { return s.hwipVersion }
