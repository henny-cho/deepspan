// SPDX-License-Identifier: Apache-2.0
package hwip

import (
	"context"
	"encoding/binary"
	"log/slog"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/durationpb"

	deepspanv1 "github.com/myorg/deepspan/l5-gen/go/deepspan/v1"
)

// Service implements deepspanv1connect.HwipServiceHandler.
type Service struct {
	sub Submitter
}

// NewService creates a Service backed by the shm RegMap (simulation mode).
// Pass shmName="" for unit-test / no-hardware mode (stub responses).
func NewService(shmName string) *Service {
	return &Service{sub: newShmClient(shmName)}
}

// newServiceWithSubmitter injects any Submitter — used by CgoClient and tests.
func newServiceWithSubmitter(s Submitter) *Service {
	return &Service{sub: s}
}

func (s *Service) ListDevices(
	ctx context.Context,
	req *connect.Request[deepspanv1.ListDevicesRequest],
) (*connect.Response[deepspanv1.ListDevicesResponse], error) {
	slog.DebugContext(ctx, "ListDevices")
	return connect.NewResponse(&deepspanv1.ListDevicesResponse{
		Devices: []*deepspanv1.DeviceInfo{{
			DeviceId:   "hwip0",
			DevicePath: "/dev/hwip0",
			State:      deepspanv1.DeviceState_DEVICE_STATE_READY,
		}},
	}), nil
}

func (s *Service) GetDeviceStatus(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetDeviceStatusRequest],
) (*connect.Response[deepspanv1.GetDeviceStatusResponse], error) {
	slog.DebugContext(ctx, "GetDeviceStatus", "device_id", req.Msg.DeviceId)
	return connect.NewResponse(&deepspanv1.GetDeviceStatusResponse{
		Info: &deepspanv1.DeviceInfo{
			DeviceId: req.Msg.DeviceId,
			State:    deepspanv1.DeviceState_DEVICE_STATE_READY,
		},
	}), nil
}

func (s *Service) SubmitRequest(
	ctx context.Context,
	req *connect.Request[deepspanv1.SubmitRequestRequest],
) (*connect.Response[deepspanv1.SubmitRequestResponse], error) {
	slog.DebugContext(ctx, "SubmitRequest",
		"device_id", req.Msg.DeviceId,
		"opcode", req.Msg.Opcode,
	)

	// Parse arg0/arg1 from the first 8 bytes of payload (little-endian).
	var arg0, arg1 uint32
	if len(req.Msg.Payload) >= 4 {
		arg0 = binary.LittleEndian.Uint32(req.Msg.Payload[:4])
	}
	if len(req.Msg.Payload) >= 8 {
		arg1 = binary.LittleEndian.Uint32(req.Msg.Payload[4:8])
	}

	start := time.Now()
	rstatus, rdata0, rdata1, err := s.sub.SubmitCmd(req.Msg.Opcode, arg0, arg1, req.Msg.TimeoutMs)
	elapsed := time.Since(start)

	if err != nil {
		slog.WarnContext(ctx, "SubmitCmd error", "err", err)
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	// Pack result_data0 + result_data1 as 8-byte little-endian result payload.
	result := make([]byte, 8)
	binary.LittleEndian.PutUint32(result[:4], rdata0)
	binary.LittleEndian.PutUint32(result[4:], rdata1)

	slog.InfoContext(ctx, "SubmitCmd ok",
		"opcode", req.Msg.Opcode,
		"result_status", rstatus,
		"result_data0", rdata0,
		"latency_ms", elapsed.Milliseconds(),
	)

	return connect.NewResponse(&deepspanv1.SubmitRequestResponse{
		RequestId: req.Msg.Opcode,
		Status:    rstatus,
		Result:    result,
		Latency:   durationpb.New(elapsed),
	}), nil
}

func (s *Service) StreamEvents(
	ctx context.Context,
	req *connect.Request[deepspanv1.StreamEventsRequest],
	stream *connect.ServerStream[deepspanv1.DeviceEvent],
) error {
	slog.DebugContext(ctx, "StreamEvents", "device_id", req.Msg.DeviceId)
	<-ctx.Done()
	return nil
}
