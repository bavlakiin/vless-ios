// Package vlesscore — обёртка для gomobile bind.
// Экспортирует 4 функции, которые видит Swift:
//   XrayStart(configJSON) / XrayStop()
//   Tun2SocksStart(fd, proxy, tunAddr) / Tun2SocksStop()
package vlesscore

import (
	"fmt"
	"strings"
	"sync"

	"github.com/xtls/xray-core/core"
	xjson "github.com/xtls/xray-core/infra/conf/json"
	_ "github.com/xtls/xray-core/main/distro/all" // регистрирует все inbound/outbound

	tun2socks "github.com/xjasonlyu/tun2socks/v2/core"
	"github.com/xjasonlyu/tun2socks/v2/core/option"
)

var (
	mu       sync.Mutex
	instance *core.Instance
	engine   tun2socks.Engine
)

// XrayStart запускает Xray с JSON-конфигом (SOCKS5 на 127.0.0.1:10808).
func XrayStart(configJSON string) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return fmt.Errorf("xray already running")
	}
	// нормализуем JSON (комментарии и т.п.), как это делает xray -config
	cfg, err := xjson.FromJSON([]byte(configJSON))
	if err != nil {
		return err
	}
	ins, err := core.New(cfg)
	if err != nil {
		return err
	}
	if err := ins.Start(); err != nil {
		return err
	}
	instance = ins
	return nil
}

// XrayStop останавливает Xray.
func XrayStop() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	return err
}

// Tun2SocksStart привязывает tun-дескриптор из NEPacketTunnelFlow
// к прокси (socks5://...) и начинает перекачку пакетов.
func Tun2SocksStart(fd int, proxy, tunAddr string) error {
	mu.Lock()
	defer mu.Unlock()
	if engine != nil {
		return fmt.Errorf("tun2socks already running")
	}
	eng, err := tun2socks.NewEngine(
		option.WithTunName("tun"),
		option.WithTunAddress(strings.SplitN(tunAddr, "/", 2)[0]),
		option.WithTunGW(strings.SplitN(tunAddr, "/", 2)[0]),
		option.WithTunMask("255.255.255.0"),
		option.WithTunDNS("8.8.8.8"),
		option.WithProxy(proxy),
		option.WithTunPersist(false),
	)
	if err != nil {
		return err
	}
	// NEPacketFlow даёт готовый fd; туннель уже существует, открывать не нужно
	if err := eng.InjectTunFD(fd); err != nil {
		return err
	}
	if err := eng.Start(); err != nil {
		return err
	}
	engine = eng
	return nil
}

// Tun2SocksStop останавливает перекачку.
func Tun2SocksStop() error {
	mu.Lock()
	defer mu.Unlock()
	if engine == nil {
		return nil
	}
	err := engine.Stop()
	engine = nil
	return err
}
