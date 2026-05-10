package evcore

import (
	"errors"
	"syscall"

	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
)

type mihomoRunner struct{}

func (m *mihomoRunner) stop() error {
	executor.Shutdown()
	return nil
}

// startMihomo boots mihomo with a TUN inbound bound to the given FD.
// mihomo's RawTun.FileDescriptor is the canonical knob for "use this
// fd instead of opening utun yourself" (listener/sing_tun/server.go
// honours it on darwin via metacubex/sing-tun's Options.FileDescriptor).
// ConfigNormalizer on the Swift side is responsible for adding the
// `tun:` block; we mutate the parsed config to inject the FD.
func startMihomo(configContent string, tunFD, _ int) (coreRunner, error) {
	cfg, err := executor.ParseWithBytes([]byte(configContent))
	if err != nil {
		return nil, err
	}
	if cfg.General == nil {
		return nil, errors.New("mihomo: parsed config has no general block")
	}
	if !cfg.General.Tun.Enable {
		return nil, errors.New("mihomo: tun block is missing or disabled")
	}
	// Dup the fd so metacubex/sing-tun's Close (which closes its
	// os.File) doesn't tear down the underlying NEPacketTunnelFlow
	// utun while the Network Extension still holds the original.
	dupFd, err := syscall.Dup(tunFD)
	if err != nil {
		return nil, err
	}
	cfg.General.Tun.FileDescriptor = dupFd

	// mihomo's DefaultRawConfig sets DNSHijack to ["0.0.0.0:53"],
	// catching every DNS query at the gvisor stack and routing it
	// to resolver.DefaultService. When the user's config doesn't
	// `dns.enable: true`, DefaultService is nil and every query
	// returns SERVFAIL ("server can't be found" in Safari). Drop
	// the hijack list whenever DNS isn't enabled so queries flow
	// through as plain UDP traffic — matching Xray and sing-box,
	// which don't hijack DNS by default in this app.
	if cfg.DNS == nil || !cfg.DNS.Enable {
		cfg.General.Tun.DNSHijack = nil
	}

	// hub.ApplyConfig does both applyRoute (which boots the
	// external-controller HTTP/WS server via route.ReCreateServer)
	// and executor.ApplyConfig (proxies, rules, listeners).
	// executor.ApplyConfig alone does NOT start the API server,
	// which is why yacd couldn't reach 127.0.0.1:9090.
	hub.ApplyConfig(cfg)
	return &mihomoRunner{}, nil
}
