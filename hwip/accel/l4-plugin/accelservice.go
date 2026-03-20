// SPDX-License-Identifier: Apache-2.0
// accelservice.go implements deepspan_accelv1connect.AccelHwipServiceHandler
// by delegating to a Submitter (ShmClient or StubClient).
package accel

import (
	"context"
	"encoding/binary"

	"connectrpc.com/connect"

	v1 "github.com/myorg/deepspan/hwip/accel/gen/go/deepspan_accel/v1"
	"github.com/myorg/deepspan/hwip/accel/gen/go/deepspan_accel/v1/deepspan_accelv1connect"
	"github.com/myorg/deepspan/l4/server/pkg/hwip"
)

// Opcode constants (mirror gen/l4-rpc/deepspan_accel/opcodes.go).
const (
	opEcho    uint32 = 0x0001
	opProcess uint32 = 0x0002
	opStatus  uint32 = 0x0003
)

// AccelService implements deepspan_accelv1connect.AccelHwipServiceHandler.
type AccelService struct {
	deepspan_accelv1connect.UnimplementedAccelHwipServiceHandler
	sub hwip.Submitter
}

// NewAccelService returns an AccelService backed by sub.
func NewAccelService(sub hwip.Submitter) *AccelService {
	return &AccelService{sub: sub}
}

// Echo maps EchoRequest → opEcho, passes arg0/arg1 through hw registers.
func (s *AccelService) Echo(
	ctx context.Context,
	req *connect.Request[v1.EchoRequest],
) (*connect.Response[v1.EchoResponse], error) {
	_, data0, data1, err := s.sub.SubmitCmd(opEcho, req.Msg.Arg0, req.Msg.Arg1, req.Msg.TimeoutMs)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&v1.EchoResponse{
		Status: 0,
		Data0:  data0,
		Data1:  data1,
	}), nil
}

// Process maps ProcessRequest → opProcess; first 8 bytes of Data are arg0/arg1 (LE).
func (s *AccelService) Process(
	ctx context.Context,
	req *connect.Request[v1.ProcessRequest],
) (*connect.Response[v1.ProcessResponse], error) {
	var arg0, arg1 uint32
	if len(req.Msg.Data) >= 4 {
		arg0 = binary.LittleEndian.Uint32(req.Msg.Data[:4])
	}
	if len(req.Msg.Data) >= 8 {
		arg1 = binary.LittleEndian.Uint32(req.Msg.Data[4:8])
	}
	_, data0, data1, err := s.sub.SubmitCmd(opProcess, arg0, arg1, req.Msg.TimeoutMs)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	result := make([]byte, 8)
	binary.LittleEndian.PutUint32(result[:4], data0)
	binary.LittleEndian.PutUint32(result[4:], data1)
	return connect.NewResponse(&v1.ProcessResponse{Status: 0, Result: result}), nil
}

// Status maps StatusRequest → opStatus; data0 is the device status word.
func (s *AccelService) Status(
	ctx context.Context,
	req *connect.Request[v1.StatusRequest],
) (*connect.Response[v1.StatusResponse], error) {
	_, statusWord, _, err := s.sub.SubmitCmd(opStatus, 0, 0, req.Msg.TimeoutMs)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	return connect.NewResponse(&v1.StatusResponse{Status: 0, StatusWord: statusWord}), nil
}

// SubmitRequest is a generic dispatch: maps AccelOp enum → hw opcode.
func (s *AccelService) SubmitRequest(
	ctx context.Context,
	req *connect.Request[v1.SubmitRequestRequest],
) (*connect.Response[v1.SubmitRequestResponse], error) {
	var opcode uint32
	switch req.Msg.Op {
	case v1.AccelOp_ACCEL_OP_ECHO:
		opcode = opEcho
	case v1.AccelOp_ACCEL_OP_PROCESS:
		opcode = opProcess
	case v1.AccelOp_ACCEL_OP_STATUS:
		opcode = opStatus
	default:
		return nil, connect.NewError(connect.CodeInvalidArgument, nil)
	}
	var arg0, arg1 uint32
	if len(req.Msg.Payload) >= 4 {
		arg0 = binary.LittleEndian.Uint32(req.Msg.Payload[:4])
	}
	if len(req.Msg.Payload) >= 8 {
		arg1 = binary.LittleEndian.Uint32(req.Msg.Payload[4:8])
	}
	rstatus, data0, data1, err := s.sub.SubmitCmd(opcode, arg0, arg1, req.Msg.TimeoutMs)
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}
	result := make([]byte, 8)
	binary.LittleEndian.PutUint32(result[:4], data0)
	binary.LittleEndian.PutUint32(result[4:], data1)
	return connect.NewResponse(&v1.SubmitRequestResponse{
		Status: int32(rstatus),
		Result: result,
	}), nil
}
