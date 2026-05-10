package evcore

import (
	"os"
	"strconv"

	"github.com/xtls/xray-core/core"

	// Register inbound, outbound, transport handlers via init().
	_ "github.com/xtls/xray-core/main/distro/all"
	// Register the JSON config loader. Importing main/json transitively
	// pulls in infra/conf, which registers `tun` as an inbound type and
	// brings in proxy/tun whose init() registers the handler.
	_ "github.com/xtls/xray-core/main/json"
)

type xrayRunner struct {
	instance *core.Instance
}

func (x *xrayRunner) stop() error {
	if x.instance != nil {
		return x.instance.Close()
	}
	return nil
}

// startXray boots Xray with a TUN inbound bound to the given FD.
// Xray's iOS TUN path reads the FD from the env var `xray.tun.fd`
// (see proxy/tun/tun_darwin.go) — the JSON's tun inbound only
// declares the protocol; the FD comes from here. ConfigNormalizer
// on the Swift side is responsible for adding the inbound; we only
// stage the env var.
func startXray(configContent string, tunFD, _ int) (coreRunner, error) {
	if err := os.Setenv("xray.tun.fd", strconv.Itoa(tunFD)); err != nil {
		return nil, err
	}
	inst, err := core.StartInstance("json", []byte(configContent))
	if err != nil {
		return nil, err
	}
	return &xrayRunner{instance: inst}, nil
}
