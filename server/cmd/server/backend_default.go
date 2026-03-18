// SPDX-License-Identifier: Apache-2.0
//go:build !appframework_cgo

package main

import "github.com/myorg/deepspan/server/internal/hwip"

// makeHwipService creates a Service backed by the POSIX shm simulation path.
// The devices slice is ignored in this build; pass --shm-name to select the shm.
func makeHwipService(shmName string, _ []string) (*hwip.Service, error) {
	return hwip.NewService(shmName), nil
}
