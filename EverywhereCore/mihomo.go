package evcore

import (
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
)

type mihomoRunner struct{}

func (m *mihomoRunner) stop() error {
	executor.Shutdown()
	return nil
}

func startMihomo(configContent string) (coreRunner, error) {
	cfg, err := executor.ParseWithBytes([]byte(configContent))
	if err != nil {
		return nil, err
	}
	// hub.ApplyConfig does both applyRoute (which boots the
	// external-controller HTTP/WS server via route.ReCreateServer)
	// and executor.ApplyConfig (proxies, rules, listeners).
	// executor.ApplyConfig alone does NOT start the API server,
	// which is why yacd couldn't reach 127.0.0.1:9090.
	hub.ApplyConfig(cfg)
	return &mihomoRunner{}, nil
}
