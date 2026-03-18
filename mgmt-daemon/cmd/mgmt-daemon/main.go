// SPDX-License-Identifier: Apache-2.0
package main

import (
	"context"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"connectrpc.com/connect"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	deepspanv1connect "github.com/myorg/deepspan/gen/go/deepspan/v1/deepspanv1connect"
	"github.com/myorg/deepspan/mgmt-daemon/internal/openamp"
	"github.com/myorg/deepspan/mgmt-daemon/internal/service"
)

func main() {
	addr     := flag.String("addr", ":8081", "gRPC listen address")
	rpmsgDev := flag.String("rpmsg-dev", "/dev/rpmsg0", "RPMsg device path")
	sim      := flag.Bool("sim", false, "simulation mode: use /dev/null instead of rpmsg device")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug}))
	slog.SetDefault(logger)

	// OpenAMP transport
	var transport *openamp.Transport
	var err error
	if *sim {
		slog.Info("simulation mode: using /dev/null as rpmsg transport")
		var f *os.File
		f, err = os.OpenFile("/dev/null", os.O_RDWR, 0)
		if err != nil {
			slog.Error("failed to open /dev/null", "err", err)
			os.Exit(1)
		}
		transport = openamp.NewTransportFromFile(f)
	} else {
		transport, err = openamp.NewTransport(*rpmsgDev)
		if err != nil {
			slog.Error("failed to open rpmsg transport", "err", err)
			os.Exit(1)
		}
	}
	defer transport.Close()

	// gRPC service
	mgmtSvc := service.NewManagementService(transport)

	mux := http.NewServeMux()
	path, handler := deepspanv1connect.NewManagementServiceHandler(mgmtSvc,
		connect.WithCompressMinBytes(1024),
	)
	mux.Handle(path, handler)

	srv := &http.Server{
		Addr:    *addr,
		Handler: h2c.NewHandler(mux, &http2.Server{}),
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	go func() {
		slog.Info("mgmt-daemon listening", "addr", *addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")
	_ = srv.Shutdown(context.Background())
}
