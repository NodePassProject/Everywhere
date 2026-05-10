// Package evcore is the gomobile-bound entry point for Everywhere's
// networking stack. It boots one of three upstream proxy cores —
// Xray, sing-box, or mihomo — that all share a single Go runtime
// when this module is bound as one xcframework.
//
// Each core owns its own TUN inbound, fed the iOS utun file
// descriptor obtained from NEPacketTunnelProvider. There is no
// separate userland tun→socks shim.
//
// The Swift side calls (in order):
//
//	SetResourcesPath(path)                   // optional, asset dir
//	StartCore(coreType, configContent,       // boots the proxy core
//	          tunFD, mtu)                    //   with TUN attached
//
// On teardown:
//
//	StopAll()
//
// The provided configuration must declare a TUN inbound for the
// active core; ConfigNormalizer on the Swift side handles that.
package evcore

import (
	"errors"
	"fmt"
	"sync"
)

const (
	CoreTypeXray    = "xray"
	CoreTypeSingBox = "singbox"
	CoreTypeMihomo  = "mihomo"
)

var (
	mu           sync.Mutex
	coreInstance coreRunner
)

type coreRunner interface {
	stop() error
}

func Version() string { return "Everywhere Core v0.2" }

// StartCore boots the chosen proxy core with TUN attached to the
// given iOS utun file descriptor. The FD lifetime stays with the
// caller — cores that need to own a copy dup it internally.
func StartCore(coreType, configContent string, tunFD, mtu int) error {
	mu.Lock()
	defer mu.Unlock()
	if coreInstance != nil {
		return errors.New("a core is already running")
	}
	if tunFD < 0 {
		return errors.New("invalid tun file descriptor")
	}
	if mtu <= 0 {
		mtu = 1500
	}
	var (
		r   coreRunner
		err error
	)
	switch coreType {
	case CoreTypeXray:
		r, err = startXray(configContent, tunFD, mtu)
	case CoreTypeSingBox:
		r, err = startSingBox(configContent, tunFD, mtu)
	case CoreTypeMihomo:
		r, err = startMihomo(configContent, tunFD, mtu)
	default:
		return fmt.Errorf("unknown core type: %s", coreType)
	}
	if err != nil {
		return err
	}
	coreInstance = r
	return nil
}

// StopAll halts the running core. Teardown is detached: the upstream
// libraries' close paths can each take seconds (Xray drains
// outbounds, sing-box has a 10s/service timeout, mihomo cleans up
// DNS/listeners), and we don't want the Network Extension to block
// on that — iOS terminates the NE process shortly after stopTunnel
// returns, which reclaims everything anyway. Errors from the
// detached stop are intentionally dropped.
func StopAll() error {
	mu.Lock()
	prev := coreInstance
	coreInstance = nil
	mu.Unlock()

	go func() {
		defer func() { _ = recover() }()
		if prev != nil {
			_ = prev.stop()
		}
	}()
	return nil
}
