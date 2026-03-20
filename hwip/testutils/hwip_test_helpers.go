// SPDX-License-Identifier: Apache-2.0
// Package testutils provides shared test helpers for HWIP server tests.
package testutils

import (
	"testing"

	"github.com/myorg/deepspan/l4/server/pkg/hwip"
)

// StubSubmitter is a minimal hwip.Submitter for unit tests.
// It echoes the opcode back as data0.
type StubSubmitter struct {
	HwipTypeName string
}

var _ hwip.Submitter = (*StubSubmitter)(nil)

func (s *StubSubmitter) SubmitCmd(opcode, arg0, arg1 uint32, _ uint32) (uint32, uint32, uint32, error) {
	return 0, opcode, 0, nil
}

// AssertSubmitterInfo checks that sub implements hwip.SubmitterInfo
// and that HwipType() returns the expected value.
func AssertSubmitterInfo(t *testing.T, sub hwip.Submitter, wantType string) {
	t.Helper()
	info, ok := sub.(hwip.SubmitterInfo)
	if !ok {
		t.Fatalf("Submitter does not implement SubmitterInfo")
	}
	if got := info.HwipType(); got != wantType {
		t.Errorf("HwipType() = %q, want %q", got, wantType)
	}
}
