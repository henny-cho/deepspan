// SPDX-License-Identifier: Apache-2.0
// SimTransport implements Transporter for simulation / --sim mode.
// All methods return plausible stub values without touching any device file.
package openamp

import "log/slog"

// SimTransport is a no-op transport used when running without real hardware.
// It satisfies the Transporter interface and is safe for concurrent use.
type SimTransport struct{}

// NewSimTransport creates a SimTransport.
func NewSimTransport() *SimTransport {
	return &SimTransport{}
}

func (s *SimTransport) GetFirmwareInfo() (string, string, uint32, []string, error) {
	slog.Debug("SimTransport.GetFirmwareInfo: returning stub values")
	return "v0.1.0-sim", "2026-01-01T00:00:00Z", 1, []string{"sim", "echo"}, nil
}

func (s *SimTransport) SendConfig(key, value string) error {
	slog.Debug("SimTransport.SendConfig: discarding", "key", key, "value", value)
	return nil
}

func (s *SimTransport) ResetDevice(force bool) error {
	slog.Debug("SimTransport.ResetDevice: no-op", "force", force)
	return nil
}

func (s *SimTransport) ConsolePTYPath(_ string) (string, error) {
	return "/dev/pts/0", nil
}

func (s *SimTransport) Close() error { return nil }
