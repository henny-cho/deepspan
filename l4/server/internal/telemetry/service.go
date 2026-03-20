// SPDX-License-Identifier: Apache-2.0
package telemetry

import (
	"context"
	"log/slog"
	"time"

	"connectrpc.com/connect"
	"google.golang.org/protobuf/types/known/timestamppb"

	deepspanv1 "github.com/myorg/deepspan/l5/gen/deepspan/v1"
)

// Service implements deepspanv1connect.TelemetryServiceHandler.
type Service struct{}

func NewService() *Service { return &Service{} }

func (s *Service) GetTelemetry(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetTelemetryRequest],
) (*connect.Response[deepspanv1.GetTelemetryResponse], error) {
	slog.DebugContext(ctx, "GetTelemetry", "device_id", req.Msg.DeviceId)
	return connect.NewResponse(&deepspanv1.GetTelemetryResponse{
		Snapshot: &deepspanv1.TelemetrySnapshot{
			DeviceId:  req.Msg.DeviceId,
			Timestamp: timestamppb.New(time.Now()),
		},
	}), nil
}

func (s *Service) StreamTelemetry(
	ctx context.Context,
	req *connect.Request[deepspanv1.StreamTelemetryRequest],
	stream *connect.ServerStream[deepspanv1.TelemetrySnapshot],
) error {
	slog.DebugContext(ctx, "StreamTelemetry", "device_id", req.Msg.DeviceId)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case t := <-ticker.C:
			if err := stream.Send(&deepspanv1.TelemetrySnapshot{
				DeviceId:  req.Msg.DeviceId,
				Timestamp: timestamppb.New(t),
			}); err != nil {
				return err
			}
		}
	}
}
