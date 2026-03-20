// SPDX-License-Identifier: Apache-2.0
// demo server — mounts both the platform HwipService and the accel-specific
// AccelHwipService on the same HTTP/2 Cleartext port (:8080).
//
// The blank import of accel/l4-plugin fires init() which registers the "accel"
// plugin with the deepspan hwip registry before the server starts.
//
// Usage:
//
//	demo-server [-addr :8080] [-shm-name deepspan_accel_0] [-stub]
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

	// Side-effect: registers "accel" plugin with hwip.Register().
	"github.com/myorg/deepspan-hwip/accel/gen/go/deepspan_accel/v1/deepspan_accelv1connect"
	accel "github.com/myorg/deepspan-hwip/accel/l4-plugin"
	"github.com/myorg/deepspan/l4/server/pkg/hwip"
	deepspanv1connect "github.com/myorg/deepspan/l5/gen/deepspan/v1/deepspanv1connect"
)

func main() {
	addr := flag.String("addr", ":8080", "listen address")
	shmName := flag.String("shm-name", "deepspan_accel_0", "POSIX shm name (bare, without /dev/shm/)")
	stub := flag.Bool("stub", false, "force stub (no-hardware) mode even if shm exists")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	// Build the Submitter: ShmClient (simulation) or StubClient (no hw).
	var sub hwip.Submitter
	if *stub {
		slog.Info("demo-server: stub mode")
		sub = accel.NewStubClient()
	} else {
		c, err := accel.NewShmClient(accel.WithShmName("/" + *shmName))
		if err != nil {
			slog.Warn("demo-server: shm not available, falling back to stub", "err", err)
			sub = accel.NewStubClient()
		} else {
			slog.Info("demo-server: shm mode", "shm", *shmName)
			sub = c
		}
	}

	// ── Service implementations ───────────────────────────────────────────
	// Platform HwipService (generic opcode+payload API).
	hwipSvc, err := hwip.NewServiceFromRegistry("accel", *shmName)
	if err != nil {
		// Registry was populated by the blank import above; this should not fail.
		slog.Error("failed to create hwip service", "err", err)
		os.Exit(1)
	}

	// Accel-specific AccelHwipService (typed Echo/Process/Status RPCs).
	accelSvc := accel.NewAccelService(sub)

	// ── HTTP mux ──────────────────────────────────────────────────────────
	intercept := connect.WithInterceptors(logInterceptor(logger))
	mux := http.NewServeMux()

	// Platform API
	path, h := deepspanv1connect.NewHwipServiceHandler(hwipSvc, intercept)
	mux.Handle(path, h)

	// Accel-specific API
	path, h = deepspan_accelv1connect.NewAccelHwipServiceHandler(accelSvc, intercept)
	mux.Handle(path, h)

	// Info & health
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		_, _ = fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		_, _ = fmt.Fprintln(w, "deepspan demo server")
		_, _ = fmt.Fprintln(w, "")
		_, _ = fmt.Fprintln(w, "Platform API (deepspan.v1.HwipService):")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/ListDevices")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/GetDeviceStatus")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/SubmitRequest")
		_, _ = fmt.Fprintln(w, "")
		_, _ = fmt.Fprintln(w, "Accel API (deepspan_accel.v1.AccelHwipService):")
		_, _ = fmt.Fprintln(w, "  POST /deepspan_accel.v1.AccelHwipService/Echo")
		_, _ = fmt.Fprintln(w, "  POST /deepspan_accel.v1.AccelHwipService/Process")
		_, _ = fmt.Fprintln(w, "  POST /deepspan_accel.v1.AccelHwipService/Status")
		_, _ = fmt.Fprintln(w, "  POST /deepspan_accel.v1.AccelHwipService/SubmitRequest")
		_, _ = fmt.Fprintln(w, "")
		_, _ = fmt.Fprintln(w, "  GET  /healthz")
	})

	srv := &http.Server{
		Addr:    *addr,
		Handler: h2c.NewHandler(mux, &http2.Server{}),
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go func() {
		slog.Info("demo-server: listening", "addr", *addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			cancel()
		}
	}()

	<-ctx.Done()
	slog.Info("demo-server: shutting down")
	shutCtx, shutCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutCancel()
	_ = srv.Shutdown(shutCtx)
}

func logInterceptor(logger *slog.Logger) connect.Interceptor {
	return connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			resp, err := next(ctx, req)
			if err != nil {
				logger.ErrorContext(ctx, "rpc error", "proc", req.Spec().Procedure, "err", err)
			} else {
				logger.InfoContext(ctx, "rpc", "proc", req.Spec().Procedure)
			}
			return resp, err
		}
	})
}
