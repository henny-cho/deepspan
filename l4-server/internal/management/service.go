// SPDX-License-Identifier: Apache-2.0
package management

import (
	"context"
	"log/slog"
	"net/http"

	"connectrpc.com/connect"

	deepspanv1 "github.com/myorg/deepspan/l5-gen/go/deepspan/v1"
	deepspanv1connect "github.com/myorg/deepspan/l5-gen/go/deepspan/v1/deepspanv1connect"
)

// Service proxies ManagementService RPCs to the mgmt-daemon.
type Service struct {
	client deepspanv1connect.ManagementServiceClient
}

func NewService(mgmtAddr string) *Service {
	client := deepspanv1connect.NewManagementServiceClient(
		http.DefaultClient,
		"http://"+mgmtAddr,
	)
	return &Service{client: client}
}

func (s *Service) GetFirmwareInfo(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetFirmwareInfoRequest],
) (*connect.Response[deepspanv1.GetFirmwareInfoResponse], error) {
	slog.DebugContext(ctx, "proxy GetFirmwareInfo")
	resp, err := s.client.GetFirmwareInfo(ctx, req)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(resp.Msg), nil
}

func (s *Service) ResetDevice(
	ctx context.Context,
	req *connect.Request[deepspanv1.ResetDeviceRequest],
) (*connect.Response[deepspanv1.ResetDeviceResponse], error) {
	slog.DebugContext(ctx, "proxy ResetDevice")
	resp, err := s.client.ResetDevice(ctx, req)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(resp.Msg), nil
}

func (s *Service) PushConfig(
	ctx context.Context,
	req *connect.Request[deepspanv1.PushConfigRequest],
) (*connect.Response[deepspanv1.PushConfigResponse], error) {
	slog.DebugContext(ctx, "proxy PushConfig")
	resp, err := s.client.PushConfig(ctx, req)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(resp.Msg), nil
}

func (s *Service) GetConsolePath(
	ctx context.Context,
	req *connect.Request[deepspanv1.GetConsolePathRequest],
) (*connect.Response[deepspanv1.GetConsolePathResponse], error) {
	slog.DebugContext(ctx, "proxy GetConsolePath")
	resp, err := s.client.GetConsolePath(ctx, req)
	if err != nil {
		return nil, err
	}
	return connect.NewResponse(resp.Msg), nil
}
