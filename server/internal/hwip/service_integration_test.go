// SPDX-License-Identifier: Apache-2.0
// Integration tests: spin up a real httptest.Server and exercise the ConnectRPC
// handler over an actual HTTP/1.1 round-trip.
package hwip_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"connectrpc.com/connect"

	deepspanv1 "github.com/myorg/deepspan/gen/go/deepspan/v1"
	deepspanv1connect "github.com/myorg/deepspan/gen/go/deepspan/v1/deepspanv1connect"
	"github.com/myorg/deepspan/server/internal/hwip"
)

// newTestServer returns an httptest.Server with the HwipService handler mounted.
func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	path, handler := deepspanv1connect.NewHwipServiceHandler(hwip.NewService())
	mux.Handle(path, handler)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func TestIntegration_ListDevices(t *testing.T) {
	srv := newTestServer(t)

	client := deepspanv1connect.NewHwipServiceClient(srv.Client(), srv.URL)
	resp, err := client.ListDevices(context.Background(),
		connect.NewRequest(&deepspanv1.ListDevicesRequest{}))
	if err != nil {
		t.Fatalf("ListDevices: %v", err)
	}
	if len(resp.Msg.Devices) == 0 {
		t.Fatal("expected at least one device in response")
	}
	if resp.Msg.Devices[0].DeviceId == "" {
		t.Error("expected non-empty device_id")
	}
}

func TestIntegration_GetDeviceStatus(t *testing.T) {
	srv := newTestServer(t)

	client := deepspanv1connect.NewHwipServiceClient(srv.Client(), srv.URL)
	resp, err := client.GetDeviceStatus(context.Background(),
		connect.NewRequest(&deepspanv1.GetDeviceStatusRequest{DeviceId: "hwip0"}))
	if err != nil {
		t.Fatalf("GetDeviceStatus: %v", err)
	}
	if resp.Msg.Info == nil {
		t.Fatal("expected non-nil Info in response")
	}
	if resp.Msg.Info.State == deepspanv1.DeviceState_DEVICE_STATE_UNSPECIFIED {
		t.Error("expected non-zero device state")
	}
}

func TestIntegration_SubmitRequest(t *testing.T) {
	srv := newTestServer(t)

	client := deepspanv1connect.NewHwipServiceClient(srv.Client(), srv.URL)
	resp, err := client.SubmitRequest(context.Background(),
		connect.NewRequest(&deepspanv1.SubmitRequestRequest{
			DeviceId: "hwip0",
			Opcode:   1,
		}))
	if err != nil {
		t.Fatalf("SubmitRequest: %v", err)
	}
	if resp.Msg.RequestId == 0 && resp.Msg.Status != 0 {
		t.Error("expected successful SubmitRequest response")
	}
}
