// SPDX-License-Identifier: Apache-2.0
// hwsim — pure-Go POSIX shared-memory hardware simulator.
//
// Creates /dev/shm/<name> and exposes the ACCEL register map (0x200 bytes)
// plus a stats block (32 bytes at 0x200).  Processes ECHO, PROCESS, STATUS
// commands in a tight poll loop so the full demo stack needs no C++.
//
// Usage:
//
//	hwsim [-name deepspan_accel_0] [-verbose]
package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

// Register offsets (must match shmclient.go and run.go).
const (
	regCtrl         = 0x0000
	regStatus       = 0x0004
	regIrqStatus    = 0x0008
	regIrqEnable    = 0x000C
	regVersion      = 0x0010
	regCapabilities = 0x0014
	regCmdOpcode    = 0x0100
	regCmdArg0      = 0x0104
	regCmdArg1      = 0x0108
	regResultStatus = 0x0110
	regResultData0  = 0x0114
	regResultData1  = 0x0118

	// Stats block at 0x200 (matches run.go shmStatsBase).
	statsBase          = 0x200
	offStatsCmdCount   = statsBase + 0  // uint64
	offStatsStartTime  = statsBase + 8  // uint64 (unix seconds)
	offStatsLastOpcode = statsBase + 16 // uint32
	offStatsLastResult = statsBase + 20 // uint32
	offStatsFwCmdCount = statsBase + 24 // uint64
	shmTotalSize       = statsBase + 32

	ctrlReset   uint32 = 1 << 0
	ctrlStart   uint32 = 1 << 1
	statusReady uint32 = 1 << 0
	statusBusy  uint32 = 1 << 1
	statusError uint32 = 1 << 2

	opEcho    uint32 = 0x0001
	opProcess uint32 = 0x0002
	opStatus  uint32 = 0x0003

	hwVersion uint32 = 0x00010000 // v1.0.0
	hwCaps    uint32 = 0x7        // DMA | IRQ | MULTI
)

var le = binary.LittleEndian

func r32(mem []byte, off int) uint32    { return le.Uint32(mem[off:]) }
func w32(mem []byte, off int, v uint32) { le.PutUint32(mem[off:], v) }
func w64(mem []byte, off int, v uint64) { le.PutUint64(mem[off:], v) }

func main() {
	name := flag.String("name", "deepspan_accel_0", "POSIX shm basename (without /dev/shm/)")
	verbose := flag.Bool("verbose", false, "log every command")
	flag.Parse()

	path := filepath.Join("/dev/shm", *name)

	// Create or truncate the shm file.
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0o666)
	if err != nil {
		slog.Error("cannot create shm", "path", path, "err", err)
		os.Exit(1)
	}
	if err := f.Truncate(shmTotalSize); err != nil {
		slog.Error("truncate failed", "err", err)
		os.Exit(1)
	}

	// mmap the file into our address space.
	mem, err := syscall.Mmap(int(f.Fd()), 0, shmTotalSize,
		syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_SHARED)
	if err != nil {
		slog.Error("mmap failed", "err", err)
		os.Exit(1)
	}
	defer func() {
		_ = syscall.Munmap(mem)
		_ = f.Close()
		_ = os.Remove(path)
		slog.Info("hwsim: shm removed", "path", path)
	}()

	// Initialise static registers.
	w32(mem, regVersion, hwVersion)
	w32(mem, regCapabilities, hwCaps)
	w32(mem, regStatus, statusReady)
	w64(mem, offStatsStartTime, uint64(time.Now().Unix()))
	slog.Info("hwsim: ready", "path", path,
		"version", fmt.Sprintf("0x%08X", hwVersion),
		"caps", fmt.Sprintf("0x%08X", hwCaps))

	// Graceful shutdown on SIGINT/SIGTERM.
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	var cmdCount uint64
	ticker := time.NewTicker(100 * time.Microsecond)
	defer ticker.Stop()

	for {
		select {
		case <-sigCh:
			slog.Info("hwsim: shutting down", "cmds_processed", cmdCount)
			return
		case <-ticker.C:
			ctrl := r32(mem, regCtrl)

			if ctrl&ctrlReset != 0 {
				w32(mem, regCtrl, 0)
				w32(mem, regStatus, statusReady)
				continue
			}
			if ctrl&ctrlStart == 0 {
				continue
			}

			// Command arrived — set BUSY, clear READY.
			w32(mem, regStatus, statusBusy)

			opcode := r32(mem, regCmdOpcode)
			arg0 := r32(mem, regCmdArg0)
			arg1 := r32(mem, regCmdArg1)

			if *verbose {
				slog.Info("hwsim: cmd",
					"opcode", fmt.Sprintf("0x%04X", opcode),
					"arg0", fmt.Sprintf("0x%08X", arg0),
					"arg1", fmt.Sprintf("0x%08X", arg1))
			}

			var resStatus, data0, data1 uint32
			switch opcode {
			case opEcho:
				// Return arg0/arg1 unchanged.
				data0, data1 = arg0, arg1
			case opProcess:
				// Sum and XOR — simple ALU demo.
				data0 = arg0 + arg1
				data1 = arg0 ^ arg1
			case opStatus:
				// Return hw version as status word.
				data0 = hwVersion
				data1 = hwCaps
			default:
				resStatus = 0xFF // unknown opcode
			}

			w32(mem, regResultStatus, resStatus)
			w32(mem, regResultData0, data0)
			w32(mem, regResultData1, data1)

			// Set READY in STATUS (for monitoring dashboard), then clear START in
			// CTRL.  ShmClient polls CTRL for START==0 as the completion signal, so
			// CTRL must be cleared last to avoid a race where the client reads stale
			// results before the write above completes.
			w32(mem, regStatus, statusReady)
			w32(mem, regCtrl, 0) // ← completion signal: client sees START cleared

			// Update stats block.
			cmdCount++
			w64(mem, offStatsCmdCount, cmdCount)
			w32(mem, offStatsLastOpcode, opcode)
			w32(mem, offStatsLastResult, resStatus)

			if *verbose {
				slog.Info("hwsim: result",
					"status", resStatus,
					"data0", fmt.Sprintf("0x%08X", data0),
					"data1", fmt.Sprintf("0x%08X", data1),
					"total", cmdCount)
			}
		}
	}
}
