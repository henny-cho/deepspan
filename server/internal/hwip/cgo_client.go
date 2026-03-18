// SPDX-License-Identifier: Apache-2.0
//go:build appframework_cgo

package hwip

/*
#cgo CXXFLAGS: -std=c++23 -I${SRCDIR}/cgo
#cgo LDFLAGS: -L${SRCDIR}/cgo/build -ldeepspan_hwip_cgo -L${SRCDIR}/../../../appframework/build -ldeepspan-appframework -L${SRCDIR}/../../../appframework/build/userlib -ldeepspan-userlib -lstdc++ -luring

#include "cgo/appframework_cgo.h"
#include <stdlib.h>
*/
import "C"

import (
	"errors"
	"fmt"
	"unsafe"
)

// cgoErr* constants must match CGO_* in appframework_cgo.cpp.
const (
	cgoErrOK       = 0
	cgoErrCircuit  = 1
	cgoErrNoDevice = 2
	cgoErrIO       = 3
)

// CgoClient routes HWIP commands through the C++ SessionManager (DevicePool +
// CircuitBreaker) using io_uring URING_CMD on the real /dev/hwipN devices.
// It satisfies the Submitter interface.
type CgoClient struct {
	handle unsafe.Pointer // *SessionHandle from deepspan_session_create()
}

// NewCgoClient opens SessionManager for the given device paths.
// queueDepth=0 uses the default (64).
func NewCgoClient(devicePaths []string, queueDepth uint) (*CgoClient, error) {
	if len(devicePaths) == 0 {
		return nil, errors.New("cgo_client: at least one device path required")
	}

	// Build C string array.
	cPaths := make([]*C.char, len(devicePaths))
	for i, p := range devicePaths {
		cPaths[i] = C.CString(p)
	}
	defer func() {
		for _, cp := range cPaths {
			C.free(unsafe.Pointer(cp))
		}
	}()

	handle := C.deepspan_session_create(
		(**C.char)(unsafe.Pointer(&cPaths[0])),
		C.int(len(cPaths)),
		C.uint(queueDepth),
	)
	if handle == nil {
		return nil, fmt.Errorf("cgo_client: deepspan_session_create failed (devices: %v)", devicePaths)
	}

	return &CgoClient{handle: handle}, nil
}

// Close destroys the underlying SessionManager. Safe to call multiple times.
func (c *CgoClient) Close() {
	if c.handle != nil {
		C.deepspan_session_destroy(c.handle)
		c.handle = nil
	}
}

// SubmitCmd implements Submitter.
func (c *CgoClient) SubmitCmd(opcode, arg0, arg1, timeoutMs uint32) (status, data0, data1 uint32, err error) {
	if c.handle == nil {
		return 0, 0, 0, errors.New("cgo_client: session not open")
	}

	res := C.deepspan_session_submit(
		c.handle,
		C.uint32_t(opcode),
		C.uint32_t(arg0),
		C.uint32_t(arg1),
		C.uint32_t(timeoutMs),
	)

	switch int(res.err_code) {
	case cgoErrOK:
		return uint32(res.status), uint32(res.result_lo), uint32(res.result_hi), nil
	case cgoErrCircuit:
		return 0, 0, 0, errors.New("cgo_client: circuit breaker open")
	case cgoErrNoDevice:
		return 0, 0, 0, errors.New("cgo_client: no available device")
	case cgoErrIO:
		return 0, 0, 0, fmt.Errorf("cgo_client: io_uring error (status=%d)", int32(res.status))
	default:
		return 0, 0, 0, fmt.Errorf("cgo_client: unknown err_code=%d", int(res.err_code))
	}
}

// CircuitState returns the current CircuitBreaker state:
// 0=Closed (healthy), 1=Open (blocking), 2=HalfOpen (probing).
func (c *CgoClient) CircuitState() int {
	if c.handle == nil {
		return 1 // treat closed handle as Open
	}
	return int(C.deepspan_session_circuit_state(c.handle))
}

// NewServiceWithCgo creates a Service backed by the real hardware via CGo.
func NewServiceWithCgo(devicePaths []string) (*Service, error) {
	client, err := NewCgoClient(devicePaths, 0)
	if err != nil {
		return nil, err
	}
	return newServiceWithSubmitter(client), nil
}
