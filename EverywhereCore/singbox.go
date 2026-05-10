package evcore

import (
	"context"
	"net/netip"
	"os"
	"syscall"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	tun "github.com/sagernet/sing-tun"
	"github.com/sagernet/sing/common/control"
	"github.com/sagernet/sing/common/json"
	"github.com/sagernet/sing/common/logger"
	"github.com/sagernet/sing/common/x/list"
	"github.com/sagernet/sing/service"
)

type singBoxRunner struct {
	box *box.Box
}

func (s *singBoxRunner) stop() error {
	if s.box != nil {
		return s.box.Close()
	}
	return nil
}

func startSingBox(configContent string, tunFD, _ int) (coreRunner, error) {
	// include.Context attaches the built-in inbound/outbound/endpoint/
	// DNS-transport/service registries to the context. Without it
	// box.New cannot resolve types declared in the JSON (socks,
	// direct, vmess, …) and start fails immediately.
	ctx := include.Context(context.Background())

	// sing-box's tun inbound has no FileDescriptor field in its JSON
	// schema — the FD is plumbed via an adapter.PlatformInterface
	// whose OpenInterface is invoked while wiring the inbound.
	pi := &singBoxPlatform{tunFD: tunFD}
	ctx = service.ContextWith[adapter.PlatformInterface](ctx, pi)

	options, err := json.UnmarshalExtendedContext[option.Options](ctx, []byte(configContent))
	if err != nil {
		return nil, err
	}
	b, err := box.New(box.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		return nil, err
	}
	if err := b.Start(); err != nil {
		_ = b.Close()
		return nil, err
	}
	return &singBoxRunner{box: b}, nil
}

// singBoxPlatform is the minimal adapter.PlatformInterface needed
// to inject an existing utun fd into sing-box's tun inbound.
//
// Layout matches libbox's stub (experimental/libbox/config.go), but
// `UsePlatformInterface` returns true so the tun inbound calls
// OpenInterface, and `UnderNetworkExtension` returns true so MTU
// defaults match the iOS NE constraints.
type singBoxPlatform struct {
	tunFD       int
	myAddresses []netip.Addr
}

func (p *singBoxPlatform) Initialize(_ adapter.NetworkManager) error { return nil }

func (p *singBoxPlatform) UsePlatformAutoDetectInterfaceControl() bool { return false }
func (p *singBoxPlatform) AutoDetectInterfaceControl(_ int) error      { return nil }

func (p *singBoxPlatform) UsePlatformInterface() bool { return true }

func (p *singBoxPlatform) OpenInterface(options *tun.Options, _ option.TunPlatformOptions) (tun.Tun, error) {
	// Dup the fd so sing-tun's Close (which closes its os.File)
	// doesn't tear down the underlying NEPacketTunnelFlow utun while
	// the Network Extension still holds the original.
	dupFd, err := syscall.Dup(p.tunFD)
	if err != nil {
		return nil, err
	}
	options.FileDescriptor = dupFd
	for _, prefix := range options.Inet4Address {
		p.myAddresses = append(p.myAddresses, prefix.Addr())
	}
	for _, prefix := range options.Inet6Address {
		p.myAddresses = append(p.myAddresses, prefix.Addr())
	}
	return tun.New(*options)
}

func (p *singBoxPlatform) UsePlatformDefaultInterfaceMonitor() bool { return true }
func (p *singBoxPlatform) CreateDefaultInterfaceMonitor(_ logger.Logger) tun.DefaultInterfaceMonitor {
	return &singBoxInterfaceMonitor{}
}

func (p *singBoxPlatform) UsePlatformNetworkInterfaces() bool                  { return false }
func (p *singBoxPlatform) NetworkInterfaces() ([]adapter.NetworkInterface, error) { return nil, os.ErrInvalid }

func (p *singBoxPlatform) UnderNetworkExtension() bool              { return true }
func (p *singBoxPlatform) NetworkExtensionIncludeAllNetworks() bool { return false }

func (p *singBoxPlatform) ClearDNSCache()                         {}
func (p *singBoxPlatform) RequestPermissionForWIFIState() error   { return nil }
func (p *singBoxPlatform) ReadWIFIState() adapter.WIFIState       { return adapter.WIFIState{} }
func (p *singBoxPlatform) SystemCertificates() []string           { return nil }

func (p *singBoxPlatform) UsePlatformConnectionOwnerFinder() bool { return false }
func (p *singBoxPlatform) FindConnectionOwner(_ *adapter.FindConnectionOwnerRequest) (*adapter.ConnectionOwner, error) {
	return nil, os.ErrInvalid
}

func (p *singBoxPlatform) UsePlatformWIFIMonitor() bool                      { return false }
func (p *singBoxPlatform) UsePlatformNotification() bool                     { return false }
func (p *singBoxPlatform) SendNotification(_ *adapter.Notification) error    { return nil }
func (p *singBoxPlatform) MyInterfaceAddress() []netip.Addr                  { return p.myAddresses }

// singBoxInterfaceMonitor is a no-op DefaultInterfaceMonitor. The
// network manager calls it when running with a platform interface,
// but in NEPacketTunnelProvider we let iOS handle outbound routing
// — sing-box does not need to bind sockets to a specific underlying
// interface. Outbound auto-detect-interface options become no-ops.
type singBoxInterfaceMonitor struct{}

func (*singBoxInterfaceMonitor) Start() error                         { return nil }
func (*singBoxInterfaceMonitor) Close() error                         { return nil }
func (*singBoxInterfaceMonitor) DefaultInterface() *control.Interface { return nil }
func (*singBoxInterfaceMonitor) OverrideAndroidVPN() bool             { return false }
func (*singBoxInterfaceMonitor) AndroidVPNEnabled() bool              { return false }
func (*singBoxInterfaceMonitor) RegisterCallback(_ tun.DefaultInterfaceUpdateCallback) *list.Element[tun.DefaultInterfaceUpdateCallback] {
	return nil
}
func (*singBoxInterfaceMonitor) UnregisterCallback(_ *list.Element[tun.DefaultInterfaceUpdateCallback]) {
}
func (*singBoxInterfaceMonitor) RegisterMyInterface(_ string) {}
func (*singBoxInterfaceMonitor) MyInterface() string          { return "" }
