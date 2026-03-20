// SPDX-License-Identifier: Apache-2.0
// Package service implements the ManagementService ConnectRPC handler.
package service

import (
	"context"
	"log/slog"

	"connectrpc.com/connect"

	"github.com/myorg/deepspan/l4/mgmt-daemon/internal/openamp"
	deepspanv1 "github.com/myorg/deepspan/l5/gen/deepspan/v1"
)

// ManagementService implements deepspanv1connect.ManagementServiceHandler.
type ManagementService struct {
	transport openamp.Transporter
}

func NewManagementService(t openamp.Transporter) *ManagementService {
	return &ManagementService{transport: t}
}

func (s *ManagementService) GetFirmwareInfo(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetFirmwareInfoRequest],
) (*connect.Response[deepspanv1.GetFirmwareInfoResponse], error) {
	slog.DebugContext(ctx, "GetFirmwareInfo", "device_id", req.Msg.DeviceId)

	fwVer, buildDate, protoVer, features, err := s.transport.GetFirmwareInfo()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&deepspanv1.GetFirmwareInfoResponse{
		FwVersion:       fwVer,
		BuildDate:       buildDate,
		ProtocolVersion: protoVer,
		Features:        features,
	}), nil
}

func (s *ManagementService) ResetDevice(
	ctx context.Context,
	req *connect.Request[deepspanv1.ResetDeviceRequest],
) (*connect.Response[deepspanv1.ResetDeviceResponse], error) {
	slog.DebugContext(ctx, "ResetDevice", "device_id", req.Msg.DeviceId, "force", req.Msg.Force)

	if err := s.transport.ResetDevice(req.Msg.Force); err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&deepspanv1.ResetDeviceResponse{
		Success: true,
		Message: "reset initiated",
	}), nil
}

func (s *ManagementService) PushConfig(
	ctx context.Context,
	req *connect.Request[deepspanv1.PushConfigRequest],
) (*connect.Response[deepspanv1.PushConfigResponse], error) {
	slog.DebugContext(ctx, "PushConfig", "device_id", req.Msg.DeviceId, "keys", len(req.Msg.Config))

	var rejectedKeys []string
	for k, v := range req.Msg.Config {
		if err := s.transport.SendConfig(k, v); err != nil {
			slog.WarnContext(ctx, "config key rejected", "key", k, "err", err)
			rejectedKeys = append(rejectedKeys, k)
		}
	}
	return connect.NewResponse(&deepspanv1.PushConfigResponse{
		Success:      len(rejectedKeys) == 0,
		RejectedKeys: rejectedKeys,
	}), nil
}

func (s *ManagementService) GetConsolePath(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetConsolePathRequest],
) (*connect.Response[deepspanv1.GetConsolePathResponse], error) {
	slog.DebugContext(ctx, "GetConsolePath", "device_id", req.Msg.DeviceId)

	ptyPath, err := s.transport.ConsolePTYPath(req.Msg.DeviceId)
	if err != nil {
		return nil, connect.NewError(connect.CodeNotFound, err)
	}
	return connect.NewResponse(&deepspanv1.GetConsolePathResponse{
		PtyPath: ptyPath,
	}), nil
}
