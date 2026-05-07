package evcore

import (
	"github.com/xtls/xray-core/core"

	// Register inbound, outbound, transport handlers via init().
	_ "github.com/xtls/xray-core/main/distro/all"
	// Register the JSON config loader.
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

func startXray(configContent string) (coreRunner, error) {
	inst, err := core.StartInstance("json", []byte(configContent))
	if err != nil {
		return nil, err
	}
	return &xrayRunner{instance: inst}, nil
}
