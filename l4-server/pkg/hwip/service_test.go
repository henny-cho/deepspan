// SPDX-License-Identifier: Apache-2.0
package hwip_test

import (
	"context"
	"testing"

	"connectrpc.com/connect"

	"github.com/myorg/deepspan/l4-server/pkg/hwip"
	deepspanv1 "github.com/myorg/deepspan/l5-gen/go/deepspan/v1"
)

func TestListDevices(t *testing.T) {
	svc := hwip.NewService("")
	resp, err := svc.ListDevices(context.Background(),
		connect.NewRequest(&deepspanv1.ListDevicesRequest{}),
	)
	if err != nil {
		t.Fatalf("ListDevices error: %v", err)
	}
	if len(resp.Msg.Devices) == 0 {
		t.Fatal("expected at least one device")
	}
}

func TestGetDeviceStatus(t *testing.T) {
	svc := hwip.NewService("")
	resp, err := svc.GetDeviceStatus(context.Background(),
		connect.NewRequest(&deepspanv1.GetDeviceStatusRequest{DeviceId: "hwip0"}),
	)
	if err != nil {
		t.Fatalf("GetDeviceStatus error: %v", err)
	}
	if resp.Msg.Info == nil {
		t.Fatal("expected non-nil Info in response")
	}
	if resp.Msg.Info.State == deepspanv1.DeviceState_DEVICE_STATE_UNSPECIFIED {
		t.Fatal("expected a non-zero device state")
	}
}
