// Package vlesscore — обёртка для gomobile bind.
//
// Экспортирует в приложение (после сборки имена получают префикс Vlesscore):
//
//	XrayStart(configJSON) / XrayStop()              — ядро Xray (VLESS-outbound, SOCKS5-вход)
//	TunStart(sink, proxyAddr, mtu, udpTimeoutSec)   — userspace TCP/IP-стек (lwIP) -> SOCKS5
//	TunInput(pkt)                                   — IP-пакет из TUN внутрь стека
//	TunStop()                                       — остановка стека
//	PacketSink                                      — интерфейс приёмника пакетов (реализуется в Swift)
//
// Стек go-tun2socks работает БЕЗ файлового дескриптора TUN: пакеты приходят
// через TunInput (из NEPacketTunnelFlow.readPackets), уходят через PacketSink
// (в NEPacketTunnelFlow.writePackets). Приватные KVC-трюки не используются.
package vlesscore

import (
	"errors"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/eycorsican/go-tun2socks/core"
	"github.com/eycorsican/go-tun2socks/proxy/socks"

	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all" // регистрирует все inbound/outbound
)

var (
	mu       sync.Mutex
	instance *xcore.Instance
	stack    core.LWIPStack
	sink     PacketSink
)

// PacketSink получает исходящие IP-пакеты из TCP/IP-стека.
type PacketSink interface {
	WritePacket(pkt []byte) error
}

// XrayStart запускает ядро Xray с JSON-конфигом.
func XrayStart(configJSON string) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		return errors.New("xray already running")
	}
	cfg, err := serial.DecodeJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return err
	}
	pb, err := cfg.Build()
	if err != nil {
		return err
	}
	ins, err := xcore.New(pb)
	if err != nil {
		return err
	}
	if err = ins.Start(); err != nil {
		return err
	}
	instance = ins
	return nil
}

// XrayStop останавливает ядро Xray.
func XrayStop() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	instance.Close()
	instance = nil
	return nil
}

// TunStart поднимает userspace TCP/IP-стек (lwIP) и направляет все
// соединения в SOCKS5-прокси proxyAddr (обычно "127.0.0.1:10808").
//
// sink реализуется на стороне приложения: каждый исходящий IP-пакет
// передаётся в sink.WritePacket (в Swift — запись в packetFlow).
func TunStart(sinkArg PacketSink, proxyAddr string, mtu int, udpTimeoutSec int) error {
	mu.Lock()
	defer mu.Unlock()
	if stack != nil {
		return errors.New("tun already running")
	}
	ta, err := net.ResolveTCPAddr("tcp", proxyAddr)
	if err != nil {
		return err
	}
	host := ta.IP.String()
	port := uint16(ta.Port)
	timeout := time.Duration(udpTimeoutSec) * time.Second

	core.RegisterTCPConnHandler(socks.NewTCPHandler(host, port))
	core.RegisterUDPConnHandler(socks.NewUDPHandler(host, port, timeout))

	s := sinkArg
	core.RegisterOutputFn(func(data []byte) (int, error) {
		if err := s.WritePacket(data); err != nil {
			return 0, err
		}
		return len(data), nil
	})

	stack = core.NewLWIPStack()
	sink = s
	_ = mtu // MTU задан внутри стека (1500); MTU TUN настраивается в приложении
	return nil
}

// TunInput подаёт один IP-пакет из TUN в стек. Вызывается для каждого
// пакета из NEPacketTunnelFlow.readPackets.
func TunInput(pkt []byte) {
	mu.Lock()
	defer mu.Unlock()
	if stack == nil || len(pkt) == 0 {
		return
	}
	_, _ = stack.Write(pkt)
}

// TunStop останавливает стек и закрывает все соединения.
func TunStop() error {
	mu.Lock()
	defer mu.Unlock()
	if stack == nil {
		return nil
	}
	err := stack.Close()
	stack = nil
	sink = nil
	return err
}

// compile-time проверки интерфейсов
var (
	_ io.Writer = stack
	_ PacketSink = sink
)
