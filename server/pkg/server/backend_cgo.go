// SPDX-License-Identifier: Apache-2.0
//go:build appframework_cgo

package server

import (
	"fmt"

	"github.com/myorg/deepspan/server/pkg/hwip"
)

// makeHwipService creates a Service backed by real hardware via CGo when
// device paths are provided, otherwise falls back to the hwip registry (shm).
func makeHwipService(hwipType, shmName string, devices []string) (*hwip.Service, error) {
	if len(devices) > 0 {
		svc, err := hwip.NewServiceWithCgo(devices)
		if err != nil {
			return nil, fmt.Errorf("CGo backend: %w", err)
		}
		return svc, nil
	}
	return hwip.NewServiceFromRegistry(hwipType, shmName)
}
