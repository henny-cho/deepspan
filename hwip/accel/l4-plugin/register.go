// SPDX-License-Identifier: Apache-2.0
// register.go registers the "accel" HWIP plugin with the deepspan platform
// hwip registry.  Import this package (or any package in accel/l4-plugin) for
// its side-effect init() to fire before serverapp.Run().
package accel

import (
	"log/slog"

	"github.com/myorg/deepspan/l4/server/pkg/hwip"
)

func init() {
	hwip.Register("accel", func(shmName string) hwip.Submitter {
		if shmName == "" || shmName == "stub" {
			slog.Info("accel: using stub (no-hardware) mode")
			return NewStubClient()
		}
		// shmName is the bare name (e.g. "deepspan_accel_0");
		// ShmClient prepends "/" to form the POSIX shm path.
		c, err := NewShmClient(WithShmName("/" + shmName))
		if err != nil {
			slog.Warn("accel: shm open failed, falling back to stub",
				"shm", shmName, "err", err)
			return NewStubClient()
		}
		slog.Info("accel: ShmClient ready", "shm", shmName)
		return c
	})
}
