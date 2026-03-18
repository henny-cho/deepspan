// SPDX-License-Identifier: Apache-2.0
// Package openamp provides RPMsg channel access for OpenAMP hypervisorless virtio.
package openamp

import (
	"encoding/binary"
	"fmt"
	"os"
	"sync"
)

// Transport wraps RPMsg character device file access.
// In production this talks to /dev/rpmsgN created by the kernel virtio-rpmsg driver.
// In simulation it talks to a named pipe or Unix socket created by the hw-model.
type Transport struct {
	mu      sync.Mutex
	devFile *os.File
	path    string
}

// NewTransport opens the RPMsg device at path.
func NewTransport(path string) (*Transport, error) {
	f, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("openamp: open %s: %w", path, err)
	}
	return &Transport{devFile: f, path: path}, nil
}

// NewTransportFromFile creates a Transport backed by an already-open file.
// Intended for testing (os.Pipe) and simulation (named pipe / Unix socket).
func NewTransportFromFile(f *os.File) *Transport {
	return &Transport{devFile: f, path: f.Name()}
}

func (t *Transport) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.devFile != nil {
		return t.devFile.Close()
	}
	return nil
}

// SendConfig writes a config key-value pair over the rpmsg-config channel.
// Wire format: [uint16 key_len][key bytes][uint16 val_len][val bytes]
func (t *Transport) SendConfig(key, value string) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	buf := make([]byte, 0, 4+len(key)+len(value))
	klen := make([]byte, 2)
	vlen := make([]byte, 2)
	binary.LittleEndian.PutUint16(klen, uint16(len(key)))
	binary.LittleEndian.PutUint16(vlen, uint16(len(value)))
	buf = append(buf, klen...)
	buf = append(buf, []byte(key)...)
	buf = append(buf, vlen...)
	buf = append(buf, []byte(value)...)

	_, err := t.devFile.Write(buf)
	return err
}

// GetFirmwareInfo reads firmware version info from the rpmsg-info channel.
// Returns: fw_version, build_date, protocol_version, features, error.
// Actual protocol: send a 1-byte query (0x01), read back a length-prefixed JSON blob.
func (t *Transport) GetFirmwareInfo() (fwVer, buildDate string, protoVer uint32, features []string, err error) {
	t.mu.Lock()
	defer t.mu.Unlock()

	// Send query byte
	if _, err = t.devFile.Write([]byte{0x01}); err != nil {
		return
	}

	// Read response: [uint16 len][JSON payload]
	header := make([]byte, 2)
	if _, err = t.devFile.Read(header); err != nil {
		return
	}
	payloadLen := binary.LittleEndian.Uint16(header)
	payload := make([]byte, payloadLen)
	if _, err = t.devFile.Read(payload); err != nil {
		return
	}

	// Parse simple fixed-field payload (not full JSON to avoid encoding/json dep)
	// In production, use encoding/json here. For now, return stub values.
	fwVer     = "v0.0.0"
	buildDate = "2026-01-01T00:00:00Z"
	protoVer  = 1
	features  = []string{}
	_ = payload
	return
}

// ConsolePTYPath returns the PTY path allocated by the OpenAMP proxy for this device.
// The kernel creates a PTY and exposes its path via sysfs or a dedicated rpmsg channel.
func (t *Transport) ConsolePTYPath(deviceID string) (string, error) {
	// In production: read from /sys/class/rpmsg/<ep>/pty_path or similar.
	// This is a stub.
	_ = deviceID
	return "/dev/pts/0", nil
}

// ResetDevice sends a reset command over the management channel.
func (t *Transport) ResetDevice(force bool) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	cmd := byte(0x10) // graceful
	if force {
		cmd = 0x11 // hard reset
	}
	_, err := t.devFile.Write([]byte{cmd})
	return err
}
