// SPDX-License-Identifier: Apache-2.0
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"connectrpc.com/connect"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	deepspanv1connect "github.com/myorg/deepspan/gen/go/deepspan/v1/deepspanv1connect"
	"github.com/myorg/deepspan/server/internal/hwip"
	"github.com/myorg/deepspan/server/internal/management"
	"github.com/myorg/deepspan/server/internal/telemetry"
)

func main() {
	addr     := flag.String("addr", ":8080", "listen address")
	mgmtAddr := flag.String("mgmt-addr", "localhost:8081", "mgmt-daemon address")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	mux := http.NewServeMux()

	// Register all services — ConnectRPC: gRPC + gRPC-Web + REST on same port
	intercept := connect.WithInterceptors(loggingInterceptor(logger))

	hwipSvc := hwip.NewService()
	path, handler := deepspanv1connect.NewHwipServiceHandler(hwipSvc, intercept)
	mux.Handle(path, handler)

	mgmtSvc := management.NewService(*mgmtAddr)
	path, handler = deepspanv1connect.NewManagementServiceHandler(mgmtSvc, intercept)
	mux.Handle(path, handler)

	telSvc := telemetry.NewService()
	path, handler = deepspanv1connect.NewTelemetryServiceHandler(telSvc, intercept)
	mux.Handle(path, handler)

	// Health check + API index
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintln(w, "Deepspan server")
		fmt.Fprintln(w, "")
		fmt.Fprintln(w, "Endpoints (ConnectRPC — JSON, gRPC, gRPC-Web):")
		fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/ListDevices")
		fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/GetDeviceStatus")
		fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/SubmitRequest")
		fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/GetFirmwareInfo")
		fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/ResetDevice")
		fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/PushConfig")
		fmt.Fprintln(w, "  POST /deepspan.v1.TelemetryService/GetTelemetry")
		fmt.Fprintln(w, "")
		fmt.Fprintln(w, "Health: GET /healthz")
	})

	srv := &http.Server{
		Addr:    *addr,
		Handler: h2c.NewHandler(mux, &http2.Server{}),
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go func() {
		slog.Info("deepspan server listening", "addr", *addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			cancel()
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutCancel()
	_ = srv.Shutdown(shutCtx)
}

// loggingInterceptor returns a unary interceptor that logs requests.
func loggingInterceptor(logger *slog.Logger) connect.Interceptor {
	return connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			resp, err := next(ctx, req)
			if err != nil {
				logger.ErrorContext(ctx, "rpc error", "procedure", req.Spec().Procedure, "err", err)
			} else {
				logger.InfoContext(ctx, "rpc ok", "procedure", req.Spec().Procedure)
			}
			return resp, err
		}
	})
}
