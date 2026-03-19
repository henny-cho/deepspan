// SPDX-License-Identifier: Apache-2.0
//go:build !appframework_cgo

package server

import "github.com/myorg/deepspan/server/pkg/hwip"

// makeHwipService creates a Service using the hwip registry.
// Use --hwip-type to select the plugin; --shm-name selects the shm backing.
// The devices slice is ignored in this (non-CGo) build.
// Returns hwip.ErrNoPlugin if the requested type has not been registered.
func makeHwipService(hwipType, shmName string, _ []string) (*hwip.Service, error) {
	return hwip.NewServiceFromRegistry(hwipType, shmName)
}
