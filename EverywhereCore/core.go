// Package evcore is the gomobile-bound entry point for Everywhere's
// networking stack. It wires tun2socks to one of three upstream proxy
// cores — Xray, sing-box, or mihomo — that all share a single Go
// runtime when this module is bound as one xcframework.
//
// The Swift side calls (in order):
//
//	StartCore(coreType, configContent) // boots the proxy core
//	StartTunnel(tunFD, socksAddr, mtu) // boots tun2socks against TUN fd
//
// On teardown:
//
//	StopAll()
//
// The provided configuration must include a SOCKS5 inbound on
// 127.0.0.1 at a known port, and that port must match socksAddr.
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
	tunRunning   bool
)

type coreRunner interface {
	stop() error
}

func Version() string { return "Everywhere Core v0.1" }

// StartCore boots the chosen proxy core.
func StartCore(coreType, configContent string) error {
	mu.Lock()
	defer mu.Unlock()
	if coreInstance != nil {
		return errors.New("a core is already running")
	}
	var (
		r   coreRunner
		err error
	)
	switch coreType {
	case CoreTypeXray:
		r, err = startXray(configContent)
	case CoreTypeSingBox:
		r, err = startSingBox(configContent)
	case CoreTypeMihomo:
		r, err = startMihomo(configContent)
	default:
		return fmt.Errorf("unknown core type: %s", coreType)
	}
	if err != nil {
		return err
	}
	coreInstance = r
	return nil
}

// StartTunnel boots tun2socks against an iOS utun file descriptor.
func StartTunnel(tunFD int, socksAddr string, mtu int) error {
	mu.Lock()
	defer mu.Unlock()
	if tunRunning {
		return errors.New("tunnel already running")
	}
	if err := startTun2socks(tunFD, socksAddr, mtu); err != nil {
		return err
	}
	tunRunning = true
	return nil
}

// StopAll halts the tunnel first, then the core.
func StopAll() error {
	mu.Lock()
	defer mu.Unlock()
	var firstErr error
	if tunRunning {
		stopTun2socks()
		tunRunning = false
	}
	if coreInstance != nil {
		if err := coreInstance.stop(); err != nil {
			firstErr = err
		}
		coreInstance = nil
	}
	return firstErr
}
