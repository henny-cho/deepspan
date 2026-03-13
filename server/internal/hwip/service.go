// SPDX-License-Identifier: Apache-2.0
package hwip

import (
	"context"
	"fmt"
	"log/slog"

	"connectrpc.com/connect"

	deepspanv1 "github.com/myorg/deepspan/gen/go/deepspan/v1"
)

// Service implements deepspanv1connect.HwipServiceHandler.
type Service struct {
	// TODO: inject DevicePool / AsyncClient once userlib CGo bridge is ready
}

func NewService() *Service { return &Service{} }

func (s *Service) ListDevices(
	ctx context.Context,
	req *connect.Request[deepspanv1.ListDevicesRequest],
) (*connect.Response[deepspanv1.ListDevicesResponse], error) {
	slog.DebugContext(ctx, "ListDevices")
	// Stub: return single simulated device
	return connect.NewResponse(&deepspanv1.ListDevicesResponse{
		Devices: []*deepspanv1.DeviceInfo{{
			DeviceId: "hwip0",
			State:    deepspanv1.DeviceState_READY,
		}},
	}), nil
}

func (s *Service) GetDeviceStatus(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetDeviceStatusRequest],
) (*connect.Response[deepspanv1.GetDeviceStatusResponse], error) {
	slog.DebugContext(ctx, "GetDeviceStatus", "device_id", req.Msg.DeviceId)
	return connect.NewResponse(&deepspanv1.GetDeviceStatusResponse{
		State:   deepspanv1.DeviceState_READY,
		Message: "ok",
	}), nil
}

func (s *Service) SubmitRequest(
	ctx context.Context,
	req *connect.Request[deepspanv1.SubmitRequestRequest],
) (*connect.Response[deepspanv1.SubmitRequestResponse], error) {
	slog.DebugContext(ctx, "SubmitRequest", "device_id", req.Msg.DeviceId, "opcode", req.Msg.Opcode)
	return connect.NewResponse(&deepspanv1.SubmitRequestResponse{
		RequestId: fmt.Sprintf("req-%s-%d", req.Msg.DeviceId, req.Msg.Opcode),
		Status:    0,
	}), nil
}

func (s *Service) StreamEvents(
	ctx context.Context,
	req *connect.Request[deepspanv1.StreamEventsRequest],
	stream *connect.ServerStream[deepspanv1.DeviceEvent],
) error {
	slog.DebugContext(ctx, "StreamEvents", "device_id", req.Msg.DeviceId)
	// Block until context cancelled — real impl would push events from kernel driver
	<-ctx.Done()
	return nil
}
