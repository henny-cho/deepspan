// SPDX-License-Identifier: Apache-2.0
//go:build !appframework_cgo

package main

import (
	"github.com/myorg/deepspan/server/internal/hwip"

	// Import accel plugin — registers AccelShmClient factory in init().
	accel "github.com/myorg/deepspan/hwip/accel/server"
)

func init() {
	// Explicitly wire the accel ShmClient into the hwip registry.
	// AccelShmClient.SubmitCmd satisfies hwip.Submitter structurally.
	hwip.Register("accel", func(shmName string) hwip.Submitter {
		return accel.NewShmClient(shmName)
	})
}

// makeHwipService creates a Service using the hwip registry.
// Use --hwip-type to select the plugin; --shm-name selects the shm backing.
// The devices slice is ignored in this (non-CGo) build.
func makeHwipService(hwipType, shmName string, _ []string) (*hwip.Service, error) {
	return hwip.NewServiceFromRegistry(hwipType, shmName)
}
