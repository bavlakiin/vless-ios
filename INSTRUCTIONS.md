# Инструкция для агента/модели на Маке

Репозиторий — VLESS-клиент для iOS 12 (iPhone 6) по образцу Happ Plus:
приложение на UIKit + Packet Tunnel extension, ядро **Xray-core 1.8.24 +
go-tun2socks 1.16.11 (lwIP)**, собираемое через gomobile.

Состояние: код переписан под реальные API зависимостей, ядро собирается
как есть. Осталась проверка на устройстве.

## Что уже сделано (не ломать)

1. **Ядро** (`core-go/vlesscore/vlesscore.go`):
   - `XrayStart/XrayStop` — конфиг через `serial.DecodeJSONConfig -> Build -> core.New`
     (официальный путь использования xray-core как библиотеки);
   - `TunStart(sink, proxyAddr, mtu, udpTimeoutSec)` — стек lwIP из go-tun2socks;
     пакеты ходят ЧЕРЕЗ ИНТЕРФЕЙС `PacketSink.WritePacket` и функцию `TunInput`,
     файловый дескриптор TUN не используется вовсе (никаких KVC-трюков);
   - сигнатуры соответствуют go-tun2socks v1.16.11:
     `core.NewLWIPStack()`, `RegisterOutputFn`, `RegisterTCPConnHandler`,
     `RegisterUDPConnHandler`, `socks.NewTCPHandler(host, port)`,
     `socks.NewUDPHandler(host, port, timeout)`.
2. **Туннель** (`VlessPacketTunnel/PacketTunnelProvider.swift`): настройки TUN,
   pump-цикл `readPackets -> TunInput`, счётчики трафика в App Group
   (`tun.bytes.in/out`), корректная остановка (`TunStop`, `XrayStop`).
3. **Приложение**: список серверов с выбором и удалением, добавление
   по QR (`AVCaptureMetadataOutput`), по ссылке из буфера, вручную,
   подписки (URL со списком ссылок или base64), статус/трафик,
   схема `vlesslite://` для импорта извне, share ссылки лонг-тапом.
4. **project.yml**: extension получает `VlessConfig.swift` + `ServerStore.swift`;
   в Info.plist есть `NSCameraUsageDescription`.

## Этап 1 — сборка ядра

```bash
brew install go@1.20 xcodegen
./scripts/build-core.sh
```

Если упадёт — смотри реальные ошибки компиляции. Возможные точки отказа:

- quic-go (транзитивная зависимость xray-core) под очень старым Xcode:
  если ругается на версию Go/C++ — собери ядро свежим Xcode (CLT),
  установку на устройство это не блокирует;
- `gomobile bind` требует именно go 1.20.x — проверь `go version`;
- после правок `vlesscore.go` сверяй имена экспортов с вызовами в Swift:
  gomobile даёт префикс `Vlesscore…` (`VlesscoreXrayStart`,
  `VlesscoreTunStart(sink, proxyAddr, mtu, udpTimeoutSec)`,
  `VlesscoreTunInput(pkt)`, `VlesscoreTunStop()`, протокол
  `VlesscorePacketSink.writePacket(_:) throws`).

## Этап 2 — Xcode

1. Замени `REPLACE_WITH_YOUR_TEAM_ID` в `project.yml` → `xcodegen`.
2. Собери оба таргета. Entitlements уже прописаны (App Group
   `group.vless.shared`, packet-tunnel-provider у обоих таргетов).

## Этап 3 — устройство

1. iPhone 6 (iOS 12) по кабелю → Run.
2. Разреши VPN-профиль при первом Connect.
3. Добавь сервер (QR/ссылка/подписка), выбери галочкой, Connect.
4. Проверь IP на 2ip.ru; трафик должен расти в шапке экрана.
5. Логи: Console.app, фильтр «VlessPacketTunnel»; debug-лог Xray —
   `"loglevel": "debug"` в `xrayConfig()`.

## Известные ограничения (честно)

- Сервер обязан поддерживать **UDP** (DNS идёт через VLESS UDP). Если нет —
  DNS умрёт; можно переключить DNS в настройках TUN на публичный и добавить
  обработчик `dnsfallback` из go-tun2socks (DNS over TCP) как отдельную задачу.
- IPv6 в TUN не поднимается (только IPv4-маршрут) — сайты только-v6 будут
  недоступны напрямую (обычно помогает fallback по A-записи).
- Приватный API не используется, но App Store всё равно потребует
  одобрения Network Extension entitlement; для личного сайдлоада достаточно
  платного аккаунта.
- Результат запушь в `main`.
