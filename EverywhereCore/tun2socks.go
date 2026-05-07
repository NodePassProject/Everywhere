package evcore

import (
	"fmt"

	"github.com/xjasonlyu/tun2socks/v2/engine"
)

func startTun2socks(tunFD int, socksAddr string, mtu int) error {
	if mtu <= 0 {
		mtu = 1500
	}
	k := &engine.Key{
		MTU:      mtu,
		Proxy:    "socks5://" + socksAddr,
		Device:   fmt.Sprintf("fd://%d", tunFD),
		LogLevel: "info",
	}
	engine.Insert(k)
	engine.Start()
	return nil
}

func stopTun2socks() {
	engine.Stop()
}
