package evcore

import (
	"context"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
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

func startSingBox(configContent string) (coreRunner, error) {
	// include.Context attaches the built-in inbound/outbound/endpoint/
	// DNS-transport/service registries to the context. Without it
	// box.New cannot resolve types declared in the JSON (socks,
	// direct, vmess, …) and start fails immediately, which iOS
	// observes as the extension dying right after the tunnel is up.
	ctx := include.Context(context.Background())

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
