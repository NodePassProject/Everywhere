package evcore

import (
	"errors"
	"os"

	mihomoConst "github.com/metacubex/mihomo/constant"
)

// SetResourcesPath configures every core to read external assets
// (geoip / geosite databases, mmdb files, certificates, cache db,
// rule sets, …) from the given directory. Call it from the iOS
// network extension before StartCore — the app group's Resources
// folder is the canonical location.
//
// Per-core wiring:
//
//   - Xray-core reads env vars `xray.location.asset` (DAT files) and
//     `xray.location.cert` (PEMs); `os.Setenv` puts them in place.
//   - mihomo's `constant.Path.HomeDir()` defaults to
//     `$HOME/.config/mihomo`; `constant.SetHomeDir(path)` overrides
//     it directly.
//   - sing-box has no global override — relative paths in its config
//     (`cache_file.path`, `geoip.path`, `geosite.path`,
//     `rule_set[].path`) resolve against the process CWD, so we
//     `os.Chdir` to the resources directory.
func SetResourcesPath(path string) error {
	if path == "" {
		return errors.New("empty resources path")
	}
	if err := os.MkdirAll(path, 0o755); err != nil {
		return err
	}
	_ = os.Setenv("xray.location.asset", path)
	_ = os.Setenv("xray.location.cert", path)
	mihomoConst.SetHomeDir(path)
	if err := os.Chdir(path); err != nil {
		return err
	}
	return nil
}
