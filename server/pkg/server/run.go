// SPDX-License-Identifier: Apache-2.0
// Package server provides the deepspan platform server entry point.
// Hwip plugin repos (e.g. deepspan-hwip) call hwip.Register() before Run().
package server

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"connectrpc.com/connect"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	deepspanv1connect "github.com/myorg/deepspan/gen/go/deepspan/v1/deepspanv1connect"
	"github.com/myorg/deepspan/server/internal/management"
	"github.com/myorg/deepspan/server/internal/telemetry"
)

// Run starts the deepspan platform server.
// Callers (e.g. hwip plugin repos) may call hwip.Register() before Run()
// to wire in their plugin.
func Run() {
	addr := flag.String("addr", ":8080", "listen address")
	mgmtAddr := flag.String("mgmt-addr", "localhost:8081", "mgmt-daemon address")
	shmName := flag.String("shm-name", "deepspan-sim", "hw-model POSIX shm name (without /dev/shm/ prefix)")
	deviceFlag := flag.String("device", "", "comma-separated /dev/hwipN paths for CGo/production mode (empty = shm simulation)")
	hwipType := flag.String("hwip-type", "accel", "hwip plugin type (accel|codec|crypto); must match a registered plugin")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	mux := http.NewServeMux()

	// Register all services — ConnectRPC: gRPC + gRPC-Web + REST on same port
	intercept := connect.WithInterceptors(loggingInterceptor(logger))

	var devicePaths []string
	if *deviceFlag != "" {
		devicePaths = splitCSV(*deviceFlag)
	}
	hwipSvc, err := makeHwipService(*hwipType, *shmName, devicePaths)
	if err != nil {
		slog.Error("failed to initialise hwip backend", "err", err)
		os.Exit(1)
	}
	path, handler := deepspanv1connect.NewHwipServiceHandler(hwipSvc, intercept)
	mux.Handle(path, handler)

	mgmtSvc := management.NewService(*mgmtAddr)
	path, handler = deepspanv1connect.NewManagementServiceHandler(mgmtSvc, intercept)
	mux.Handle(path, handler)

	telSvc := telemetry.NewService()
	path, handler = deepspanv1connect.NewTelemetryServiceHandler(telSvc, intercept)
	mux.Handle(path, handler)

	// ── Hardware monitoring endpoints ─────────────────────────────────────
	shmPath := "/dev/shm/" + *shmName

	mux.HandleFunc("/api/hw-stats", func(w http.ResponseWriter, r *http.Request) {
		stats, err := readHwStats(shmPath)
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		if err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			_ = json.NewEncoder(w).Encode(map[string]any{
				"available": false,
				"error":     err.Error(),
				"shm_path":  shmPath,
			})
			return
		}
		_ = json.NewEncoder(w).Encode(stats)
	})

	mux.HandleFunc("/monitor", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = fmt.Fprint(w, monitorHTML(*shmName))
	})

	// ── Health check + API index ──────────────────────────────────────────
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
		_, _ = fmt.Fprintln(w, "Deepspan server")
		_, _ = fmt.Fprintln(w, "")
		_, _ = fmt.Fprintln(w, "Endpoints (ConnectRPC — JSON, gRPC, gRPC-Web):")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/ListDevices")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/GetDeviceStatus")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.HwipService/SubmitRequest")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/GetFirmwareInfo")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/ResetDevice")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.ManagementService/PushConfig")
		_, _ = fmt.Fprintln(w, "  POST /deepspan.v1.TelemetryService/GetTelemetry")
		_, _ = fmt.Fprintln(w, "")
		_, _ = fmt.Fprintln(w, "Monitoring:")
		_, _ = fmt.Fprintln(w, "  GET  /monitor        — live hardware dashboard")
		_, _ = fmt.Fprintln(w, "  GET  /api/hw-stats   — hw-model register state (JSON)")
		_, _ = fmt.Fprintln(w, "  GET  /healthz        — health check")
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

// ── HW stats reader ───────────────────────────────────────────────────────────

// RegMap offsets (must match hw-model/include/deepspan/hw_model/reg_map.hpp)
const (
	offCtrl         = 0x000
	offStatus       = 0x004
	offIrqStatus    = 0x008
	offIrqEnable    = 0x00C
	offVersion      = 0x010
	offCapabilities = 0x014
	offCmdOpcode    = 0x100
	offCmdArg0      = 0x104
	offCmdArg1      = 0x108
	offResultStatus = 0x110
	offResultData0  = 0x114
	offResultData1  = 0x118

	// ShmStats offsets (at SHM_STATS_OFFSET = 0x200)
	shmStatsBase             = 0x200
	offStatsCmdCount         = shmStatsBase + 0  // uint64
	offStatsStartTime        = shmStatsBase + 8  // uint64
	offStatsLastOpcode       = shmStatsBase + 16 // uint32
	offStatsLastResultStatus = shmStatsBase + 20 // uint32
	offStatsFwCmdCount       = shmStatsBase + 24 // uint64

	shmMinSize = shmStatsBase + 32 // minimum bytes needed
)

type hwStats struct {
	Available bool   `json:"available"`
	ShmPath   string `json:"shm_path"`
	UptimeSec int64  `json:"uptime_s"`

	// RegMap fields
	VersionRaw  string `json:"version"`
	VersionStr  string `json:"version_str"`
	CapsRaw     string `json:"capabilities"`
	CapsStr     string `json:"capabilities_str"`
	StatusRaw   string `json:"status_reg"`
	StatusReady bool   `json:"status_ready"`
	StatusBusy  bool   `json:"status_busy"`
	StatusError bool   `json:"status_error"`
	IrqStatus   string `json:"irq_status"`

	// Current command registers
	CmdOpcode    string `json:"cmd_opcode"`
	CmdArg0      string `json:"cmd_arg0"`
	CmdArg1      string `json:"cmd_arg1"`
	ResultStatus string `json:"result_status"`
	ResultData0  string `json:"result_data0"`
	ResultData1  string `json:"result_data1"`

	// ShmStats fields
	CmdCount         uint64 `json:"hw_cmd_count"`
	FwCmdCount       uint64 `json:"fw_cmd_count"`
	LastOpcode       string `json:"last_opcode"`
	LastResultStatus string `json:"last_result_status"`
}

func readHwStats(shmPath string) (*hwStats, error) {
	data, err := os.ReadFile(shmPath)
	if err != nil {
		return nil, fmt.Errorf("shm not available: %w", err)
	}
	if len(data) < shmMinSize {
		return nil, fmt.Errorf("shm too small: %d bytes (need %d)", len(data), shmMinSize)
	}

	le := binary.LittleEndian
	u32 := func(off int) uint32 { return le.Uint32(data[off:]) }
	u64 := func(off int) uint64 { return le.Uint64(data[off:]) }
	h32 := func(v uint32) string { return fmt.Sprintf("0x%08X", v) }

	version := u32(offVersion)
	caps := u32(offCapabilities)
	statusR := u32(offStatus)

	capsStr := ""
	if caps&0x1 != 0 {
		capsStr += "DMA "
	}
	if caps&0x2 != 0 {
		capsStr += "IRQ "
	}
	if caps&0x4 != 0 {
		capsStr += "MULTI"
	}

	startTime := int64(u64(offStatsStartTime))
	uptime := int64(0)
	if startTime > 0 {
		uptime = time.Now().Unix() - startTime
	}

	return &hwStats{
		Available:        true,
		ShmPath:          shmPath,
		UptimeSec:        uptime,
		VersionRaw:       h32(version),
		VersionStr:       fmt.Sprintf("%d.%d.%d", (version>>16)&0xFF, (version>>8)&0xFF, version&0xFF),
		CapsRaw:          h32(caps),
		CapsStr:          capsStr,
		StatusRaw:        h32(statusR),
		StatusReady:      statusR&0x1 != 0,
		StatusBusy:       statusR&0x2 != 0,
		StatusError:      statusR&0x4 != 0,
		IrqStatus:        h32(u32(offIrqStatus)),
		CmdOpcode:        h32(u32(offCmdOpcode)),
		CmdArg0:          h32(u32(offCmdArg0)),
		CmdArg1:          h32(u32(offCmdArg1)),
		ResultStatus:     h32(u32(offResultStatus)),
		ResultData0:      h32(u32(offResultData0)),
		ResultData1:      h32(u32(offResultData1)),
		CmdCount:         u64(offStatsCmdCount),
		FwCmdCount:       u64(offStatsFwCmdCount),
		LastOpcode:       h32(u32(offStatsLastOpcode)),
		LastResultStatus: h32(u32(offStatsLastResultStatus)),
	}, nil
}

// ── Monitor HTML dashboard ────────────────────────────────────────────────────

func monitorHTML(shmName string) string {
	return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>Deepspan Hardware Monitor</title>
<style>
  body { font-family: 'Courier New', monospace; background: #0d1117; color: #c9d1d9; margin: 0; padding: 20px; }
  h1 { color: #58a6ff; border-bottom: 1px solid #30363d; padding-bottom: 10px; }
  h2 { color: #8b949e; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; margin-top: 24px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 16px; }
  .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
  .card h3 { margin: 0 0 12px; color: #58a6ff; font-size: 0.95em; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
  td { padding: 4px 8px; border-bottom: 1px solid #21262d; }
  td:first-child { color: #8b949e; width: 55%; }
  td:last-child { color: #e6edf3; font-family: monospace; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 0.8em; font-weight: bold; }
  .ok    { background: #1a4731; color: #3fb950; }
  .busy  { background: #3d2f00; color: #d29922; }
  .error { background: #3d0000; color: #f85149; }
  .off   { background: #21262d; color: #6e7681; }
  .counter { font-size: 1.8em; font-weight: bold; color: #58a6ff; }
  .ts { color: #6e7681; font-size: 0.8em; }
  #status-bar { margin-bottom: 16px; padding: 8px 12px; border-radius: 6px; font-size: 0.85em; }
  .connected    { background: #1a4731; color: #3fb950; border: 1px solid #2ea043; }
  .disconnected { background: #3d0000; color: #f85149; border: 1px solid #da3633; }
  .activity-log { height: 160px; overflow-y: auto; font-size: 0.8em; color: #8b949e; }
  .activity-log p { margin: 2px 0; }
  .activity-log .cmd  { color: #79c0ff; }
  .activity-log .res  { color: #3fb950; }
  .activity-log .warn { color: #d29922; }
</style>
</head>
<body>
<h1>⚡ Deepspan Hardware Monitor</h1>
<div id="status-bar" class="disconnected">Connecting to hw-model...</div>

<div class="grid">
  <div class="card">
    <h3>HW-Model Status</h3>
    <table id="hw-regs">
      <tr><td>Version</td><td id="r-ver">—</td></tr>
      <tr><td>Capabilities</td><td id="r-caps">—</td></tr>
      <tr><td>Status Register</td><td id="r-status">—</td></tr>
      <tr><td>IRQ Status</td><td id="r-irq">—</td></tr>
      <tr><td>Uptime</td><td id="r-uptime">—</td></tr>
    </table>
  </div>

  <div class="card">
    <h3>Command Statistics</h3>
    <div style="display:flex; gap:24px; margin-bottom:12px;">
      <div style="text-align:center;">
        <div class="counter" id="hw-cmd-count">0</div>
        <div class="ts">hw-model processed</div>
      </div>
      <div style="text-align:center;">
        <div class="counter" id="fw-cmd-count">0</div>
        <div class="ts">firmware-sim sent</div>
      </div>
    </div>
    <table>
      <tr><td>Last Opcode</td><td id="r-last-op">—</td></tr>
      <tr><td>Last Result</td><td id="r-last-res">—</td></tr>
    </table>
  </div>

  <div class="card">
    <h3>Last Command / Result</h3>
    <table>
      <tr><td>cmd_opcode</td><td id="r-cmd-op">—</td></tr>
      <tr><td>cmd_arg0</td><td id="r-cmd-a0">—</td></tr>
      <tr><td>cmd_arg1</td><td id="r-cmd-a1">—</td></tr>
      <tr><td>result_status</td><td id="r-res-st">—</td></tr>
      <tr><td>result_data0</td><td id="r-res-d0">—</td></tr>
      <tr><td>result_data1</td><td id="r-res-d1">—</td></tr>
    </table>
  </div>

  <div class="card">
    <h3>Activity Log</h3>
    <div class="activity-log" id="activity-log"></div>
  </div>
</div>

<script>
const SHM_NAME = '` + shmName + `';
let prevCmdCount = 0;
let prevFwCount = 0;
const log = document.getElementById('activity-log');

function addLog(cls, msg) {
  const p = document.createElement('p');
  p.className = cls;
  const ts = new Date().toLocaleTimeString();
  p.textContent = '[' + ts + '] ' + msg;
  log.insertBefore(p, log.firstChild);
  while (log.children.length > 50) log.removeChild(log.lastChild);
}

function badge(ok, busy, err) {
  if (err)  return '<span class="badge error">ERROR</span>';
  if (busy) return '<span class="badge busy">BUSY</span>';
  if (ok)   return '<span class="badge ok">READY</span>';
  return '<span class="badge off">UNKNOWN</span>';
}

async function refresh() {
  try {
    const r = await fetch('/api/hw-stats');
    const d = await r.json();
    const bar = document.getElementById('status-bar');

    if (!d.available) {
      bar.className = 'disconnected';
      bar.textContent = '⚠ hw-model not running — shm: ' + d.shm_path;
      return;
    }

    bar.className = 'connected';
    bar.textContent = '● hw-model connected  shm: /dev/shm/' + SHM_NAME +
                      '  uptime: ' + d.uptime_s + 's';

    document.getElementById('r-ver').textContent    = d.version + '  (v' + d.version_str + ')';
    document.getElementById('r-caps').textContent   = d.capabilities + '  ' + d.capabilities_str;
    document.getElementById('r-status').innerHTML   = badge(d.status_ready, d.status_busy, d.status_error);
    document.getElementById('r-irq').textContent    = d.irq_status;
    document.getElementById('r-uptime').textContent = d.uptime_s + 's';

    document.getElementById('hw-cmd-count').textContent = d.hw_cmd_count;
    document.getElementById('fw-cmd-count').textContent = d.fw_cmd_count;
    document.getElementById('r-last-op').textContent    = d.last_opcode;
    document.getElementById('r-last-res').textContent   = d.last_result_status;

    document.getElementById('r-cmd-op').textContent = d.cmd_opcode;
    document.getElementById('r-cmd-a0').textContent = d.cmd_arg0;
    document.getElementById('r-cmd-a1').textContent = d.cmd_arg1;
    document.getElementById('r-res-st').textContent = d.result_status;
    document.getElementById('r-res-d0').textContent = d.result_data0;
    document.getElementById('r-res-d1').textContent = d.result_data1;

    if (d.hw_cmd_count > prevCmdCount) {
      addLog('res', 'hw-model: cmd #' + (d.hw_cmd_count-1) +
             ' done  opcode=' + d.last_opcode + '  result=' + d.last_result_status);
      prevCmdCount = d.hw_cmd_count;
    }
    if (d.fw_cmd_count > prevFwCount) {
      addLog('cmd', 'fw-sim: sent cmd #' + (d.fw_cmd_count-1) +
             '  arg0=' + d.cmd_arg0 + '  arg1=' + d.cmd_arg1);
      prevFwCount = d.fw_cmd_count;
    }
  } catch (e) {
    addLog('warn', 'fetch error: ' + e.message);
  }
}

setInterval(refresh, 800);
refresh();
</script>
</body>
</html>`
}

// splitCSV splits a comma-separated string, trimming spaces, skipping empties.
func splitCSV(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// ── loggingInterceptor ────────────────────────────────────────────────────────

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
