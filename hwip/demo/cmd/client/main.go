// SPDX-License-Identifier: Apache-2.0
// demo client — exercises the full deepspan ACCEL stack over ConnectRPC.
//
// Calls both the platform HwipService and the accel-specific AccelHwipService,
// printing results in a human-readable table.
//
// Usage:
//
//	demo-client [-addr http://localhost:8080]
package main

import (
	"context"
	"encoding/binary"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"connectrpc.com/connect"

	accelv1 "github.com/myorg/deepspan-hwip/accel/gen/go/deepspan_accel/v1"
	"github.com/myorg/deepspan-hwip/accel/gen/go/deepspan_accel/v1/deepspan_accelv1connect"
	deepspanv1 "github.com/myorg/deepspan/l5/gen/deepspan/v1"
	"github.com/myorg/deepspan/l5/gen/deepspan/v1/deepspanv1connect"
)

func main() {
	addr := flag.String("addr", "http://localhost:8080", "demo-server base URL")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelWarn}))
	slog.SetDefault(logger)

	httpClient := &http.Client{}

	// ── Platform clients ──────────────────────────────────────────────────
	hwipClient := deepspanv1connect.NewHwipServiceClient(httpClient, *addr,
		connect.WithSendGzip())
	accelClient := deepspan_accelv1connect.NewAccelHwipServiceClient(httpClient, *addr,
		connect.WithSendGzip())

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	printHeader("deepspan ACCEL Demo")

	// ─── 1. Platform: ListDevices ─────────────────────────────────────────
	printSection("1. Platform HwipService — ListDevices")
	listResp, err := hwipClient.ListDevices(ctx,
		connect.NewRequest(&deepspanv1.ListDevicesRequest{}))
	mustOK(err, "ListDevices")
	for _, d := range listResp.Msg.Devices {
		fmt.Printf("   device_id=%-8s  state=%s\n", d.DeviceId, d.State)
	}

	// ─── 2. Platform: SubmitRequest (Echo opcode=1) ───────────────────────
	printSection("2. Platform HwipService — SubmitRequest (ECHO opcode=0x0001)")
	payload := make([]byte, 8)
	binary.LittleEndian.PutUint32(payload[:4], 0xDEAD_BEEF)
	binary.LittleEndian.PutUint32(payload[4:], 0x1234_5678)
	subResp, err := hwipClient.SubmitRequest(ctx,
		connect.NewRequest(&deepspanv1.SubmitRequestRequest{
			DeviceId:  "hwip0",
			Opcode:    0x0001,
			Payload:   payload,
			TimeoutMs: 1000,
		}))
	mustOK(err, "SubmitRequest/Echo")
	data0 := binary.LittleEndian.Uint32(subResp.Msg.Result[:4])
	data1 := binary.LittleEndian.Uint32(subResp.Msg.Result[4:])
	fmt.Printf("   arg0=0x%08X  arg1=0x%08X\n", uint32(0xDEADBEEF), uint32(0x12345678))
	fmt.Printf("   data0=0x%08X  data1=0x%08X  latency=%s\n",
		data0, data1, subResp.Msg.Latency.AsDuration().Round(time.Microsecond))
	check("echo arg0", data0, 0xDEADBEEF)
	check("echo arg1", data1, 0x12345678)

	// ─── 3. Accel: Echo ──────────────────────────────────────────────────
	printSection("3. AccelHwipService — Echo")
	echoResp, err := accelClient.Echo(ctx,
		connect.NewRequest(&accelv1.EchoRequest{
			DeviceId:  "hwip0",
			Arg0:      0xCAFE_BABE,
			Arg1:      0x0000_ABCD,
			TimeoutMs: 1000,
		}))
	mustOK(err, "Echo")
	fmt.Printf("   arg0=0x%08X  arg1=0x%08X\n", uint32(0xCAFEBABE), uint32(0x0000ABCD))
	fmt.Printf("   data0=0x%08X  data1=0x%08X\n", echoResp.Msg.Data0, echoResp.Msg.Data1)
	check("echo data0", echoResp.Msg.Data0, 0xCAFEBABE)
	check("echo data1", echoResp.Msg.Data1, 0x0000ABCD)

	// ─── 4. Accel: Process ───────────────────────────────────────────────
	printSection("4. AccelHwipService — Process (arg0+arg1, arg0^arg1)")
	procData := make([]byte, 8)
	binary.LittleEndian.PutUint32(procData[:4], 100)
	binary.LittleEndian.PutUint32(procData[4:], 42)
	procResp, err := accelClient.Process(ctx,
		connect.NewRequest(&accelv1.ProcessRequest{
			DeviceId:  "hwip0",
			Data:      procData,
			TimeoutMs: 1000,
		}))
	mustOK(err, "Process")
	sum := binary.LittleEndian.Uint32(procResp.Msg.Result[:4])
	xor := binary.LittleEndian.Uint32(procResp.Msg.Result[4:])
	fmt.Printf("   arg0=100  arg1=42\n")
	fmt.Printf("   sum=%d  xor=%d\n", sum, xor)
	check("process sum", sum, 142)
	check("process xor", xor, 100^42)

	// ─── 5. Accel: Status ────────────────────────────────────────────────
	printSection("5. AccelHwipService — Status")
	statusResp, err := accelClient.Status(ctx,
		connect.NewRequest(&accelv1.StatusRequest{
			DeviceId:  "hwip0",
			TimeoutMs: 1000,
		}))
	mustOK(err, "Status")
	fmt.Printf("   status_word=0x%08X  (v%d.%d.%d)\n",
		statusResp.Msg.StatusWord,
		(statusResp.Msg.StatusWord>>16)&0xFF,
		(statusResp.Msg.StatusWord>>8)&0xFF,
		statusResp.Msg.StatusWord&0xFF)

	printHeader("All checks passed")
}

// ── helpers ──────────────────────────────────────────────────────────────────

func printHeader(msg string) {
	bar := "═══════════════════════════════════════════"
	fmt.Printf("\n%s\n  %s\n%s\n", bar, msg, bar)
}

func printSection(msg string) {
	fmt.Printf("\n── %s\n", msg)
}

func mustOK(err error, op string) {
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL %s: %v\n", op, err)
		os.Exit(1)
	}
}

func check(label string, got, want uint32) {
	if got == want {
		fmt.Printf("   [OK] %s = 0x%08X\n", label, got)
	} else {
		fmt.Fprintf(os.Stderr, "   [FAIL] %s: got 0x%08X, want 0x%08X\n", label, got, want)
		os.Exit(1)
	}
}
