// SPDX-License-Identifier: Apache-2.0
package openamp_test

import (
	"encoding/binary"
	"io"
	"os"
	"testing"

	"github.com/myorg/deepspan/l4/mgmt-daemon/internal/openamp"
)

func TestNewTransport_NonexistentDevice(t *testing.T) {
	_, err := openamp.NewTransport("/dev/deepspan_nosuchdev_xxxx")
	if err == nil {
		t.Fatal("expected error for nonexistent device, got nil")
	}
}

// TestSendConfig_WireFormat verifies the on-wire encoding of SendConfig.
// Wire format: [uint16-LE key_len][key bytes][uint16-LE val_len][val bytes]
func TestSendConfig_WireFormat(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	defer func() { _ = r.Close() }()

	tr := openamp.NewTransportFromFile(w)

	const key = "log_level"
	const val = "debug"

	if err := tr.SendConfig(key, val); err != nil {
		t.Fatalf("SendConfig: %v", err)
	}
	// Close write-end so the reader sees EOF after the message.
	if err := w.Close(); err != nil {
		t.Fatalf("close pipe: %v", err)
	}

	data, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read pipe: %v", err)
	}

	// Expected total length: 2 + len(key) + 2 + len(val)
	wantLen := 2 + len(key) + 2 + len(val)
	if len(data) != wantLen {
		t.Fatalf("wire length: got %d, want %d", len(data), wantLen)
	}

	// Decode and verify each field.
	off := 0
	gotKeyLen := binary.LittleEndian.Uint16(data[off : off+2])
	off += 2
	if int(gotKeyLen) != len(key) {
		t.Errorf("key_len field: got %d, want %d", gotKeyLen, len(key))
	}
	gotKey := string(data[off : off+int(gotKeyLen)])
	off += int(gotKeyLen)
	if gotKey != key {
		t.Errorf("key: got %q, want %q", gotKey, key)
	}

	gotValLen := binary.LittleEndian.Uint16(data[off : off+2])
	off += 2
	if int(gotValLen) != len(val) {
		t.Errorf("val_len field: got %d, want %d", gotValLen, len(val))
	}
	gotVal := string(data[off : off+int(gotValLen)])
	if gotVal != val {
		t.Errorf("val: got %q, want %q", gotVal, val)
	}
}

// TestSendConfig_EmptyKeyValue checks zero-length edge cases.
func TestSendConfig_EmptyKeyValue(t *testing.T) {
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	defer func() { _ = r.Close() }()

	tr := openamp.NewTransportFromFile(w)
	if err := tr.SendConfig("", ""); err != nil {
		t.Fatalf("SendConfig: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("close pipe: %v", err)
	}

	data, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("read pipe: %v", err)
	}

	// 2-byte key_len (0) + 2-byte val_len (0) = 4 bytes total.
	if len(data) != 4 {
		t.Fatalf("wire length for empty key/val: got %d, want 4", len(data))
	}
	if kl := binary.LittleEndian.Uint16(data[0:2]); kl != 0 {
		t.Errorf("key_len: got %d, want 0", kl)
	}
	if vl := binary.LittleEndian.Uint16(data[2:4]); vl != 0 {
		t.Errorf("val_len: got %d, want 0", vl)
	}
}
