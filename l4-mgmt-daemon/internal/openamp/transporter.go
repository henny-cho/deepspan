// SPDX-License-Identifier: Apache-2.0
// Package openamp defines the Transporter interface shared by Transport
// (real RPMsg) and SimTransport (simulation / testing).
package openamp

// Transporter is the interface used by ManagementService.
// Both *Transport (production) and *SimTransport (--sim mode) implement it.
type Transporter interface {
	GetFirmwareInfo() (fwVer, buildDate string, protoVer uint32, features []string, err error)
	SendConfig(key, value string) error
	ResetDevice(force bool) error
	ConsolePTYPath(deviceID string) (string, error)
	Close() error
}
