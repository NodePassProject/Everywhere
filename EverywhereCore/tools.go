// Build tag isolates these blank imports — they exist only so `go mod`
// pins the gomobile binding packages used by `gomobile bind` at build
// time. The package never actually compiles into the framework.
//go:build tools

package evcore

import (
	_ "golang.org/x/mobile/bind"
)
