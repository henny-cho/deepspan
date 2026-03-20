// SPDX-License-Identifier: Apache-2.0
package accel_test

import (
	"testing"

	accel "github.com/myorg/deepspan/hwip/accel/l4-plugin"
	"github.com/myorg/deepspan/l4/server/pkg/hwip"
)

// Compile-time interface checks.
var _ hwip.Submitter = (*accel.ShmClient)(nil)
var _ hwip.SubmitterInfo = (*accel.ShmClient)(nil)
var _ hwip.Submitter = (*accel.StubClient)(nil)
var _ hwip.SubmitterInfo = (*accel.StubClient)(nil)

func TestStubClient_SubmitCmd(t *testing.T) {
	s := accel.NewStubClient()

	// StubClient echoes opcode as data0.
	_, data0, _, err := s.SubmitCmd(0x0001, 42, 99, 0)
	if err != nil {
		t.Fatalf("SubmitCmd: %v", err)
	}
	if data0 != 0x0001 {
		t.Errorf("data0 = 0x%04x, want 0x0001", data0)
	}
}

func TestStubClient_SubmitterInfo(t *testing.T) {
	s := accel.NewStubClient()
	if got := s.HwipType(); got != "accel" {
		t.Errorf("HwipType() = %q, want %q", got, "accel")
	}
	if s.Version() == "" {
		t.Error("Version() is empty")
	}
}

func TestNewShmClient_MissingShm(t *testing.T) {
	// No hw-model running → shm open must fail gracefully.
	_, err := accel.NewShmClient(accel.WithShmName("/deepspan_accel_nonexistent"))
	if err == nil {
		t.Fatal("expected error when shm region does not exist")
	}
}

func TestStubClient_AssertSubmitterInfo(t *testing.T) {
	// Demonstrate usage of shared testutils helper.
	s := accel.NewStubClient()
	// Manual equivalent of testutils.AssertSubmitterInfo (avoids cross-module import in same test file).
	info, ok := any(s).(interface{ HwipType() string })
	if !ok {
		t.Fatal("StubClient does not implement SubmitterInfo")
	}
	if got := info.HwipType(); got != "accel" {
		t.Errorf("HwipType() = %q, want \"accel\"", got)
	}
}
