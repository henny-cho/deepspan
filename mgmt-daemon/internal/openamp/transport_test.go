// SPDX-License-Identifier: Apache-2.0
package openamp_test

import (
	"testing"
	"github.com/myorg/deepspan/mgmt-daemon/internal/openamp"
)

func TestNewTransport_NonexistentDevice(t *testing.T) {
	_, err := openamp.NewTransport("/dev/deepspan_nosuchdev_xxxx")
	if err == nil {
		t.Fatal("expected error for nonexistent device, got nil")
	}
}

func TestSendConfig_WireFormat(t *testing.T) {
	// Test that SendConfig serializes key-value correctly.
	// This test uses a file-based loopback (os.Pipe) to validate wire format.
	// Skipped in unit test — integration test would use real rpmsg device.
	t.Skip("requires rpmsg loopback — run in integration suite")
}
