// SPDX-License-Identifier: Apache-2.0
// Package codecserver is a skeleton for the codec HWIP plugin.
//
// To implement:
//  1. Copy hwip/accel/server/shmclient.go → shmclient.go, adjust offsets.
//  2. Implement codec-specific opcodes (ENCODE=0x1, DECODE=0x2).
//  3. Run: cd hwip/codec && buf generate --template buf.gen.yaml
//  4. Register in server/cmd/server/backend_default.go:
//       import codec "github.com/myorg/deepspan/hwip/codec/server"
//       hwip.Register("codec", func(s string) hwip.Submitter { return codec.NewShmClient(s) })
//  5. Add ./hwip/codec/server to go.work.
//  6. Add "hwip/codec" to .release-please-config.json.
package codecserver

// OpEncode sends a buffer through the codec encode pipeline.
const OpEncode uint32 = 0x0001

// OpDecode sends a buffer through the codec decode pipeline.
const OpDecode uint32 = 0x0002

// OpStatus queries the codec device status register.
const OpStatus uint32 = 0x0003
