# Быстрая сборка на Маке (порядок строго такой)

## 0. Что нужно
- macOS с Xcode (для установки на iOS 12-устройство удобен старый Xcode 10.3
  на Mojave; собираться проект может и свежим Xcode)
- Apple Developer-аккаунт (**платный** — NetworkExtension без него не подписать)
- Go 1.20.x (`brew install go@1.20`), XcodeGen (`brew install xcodegen`)

## 1. Собрать ядро (5–15 минут)
```bash
cd vless-ios
./scripts/build-core.sh
```
Появится `XrayFramework/VlessCore.xcframework`:
- **Xray-core 1.8.24** — протоколы VLESS/TLS/Reality/Vision/ws/grpc;
- **go-tun2socks 1.16.11** — userspace TCP/IP-стек lwIP, работает БЕЗ
  файлового дескриптора TUN (пакеты передаются массивами через gomobile).

Первый запуск долгий: `go mod tidy` скачает зависимости, cgo скомпилирует lwIP.

## 2. Сгенерировать Xcode-проект
```bash
xcodegen
open VlessApp.xcodeproj
```

## 3. Один раз настроить в Xcode
1. В `project.yml` замените `REPLACE_WITH_YOUR_TEAM_ID` на свой Team ID и
   перегенерируйте проект (`xcodegen`), либо выберите Team в обоих таргетах
   (VlessApp и VlessPacketTunnel) → Signing & Capabilities.
2. Capabilities уже прописаны в entitlements: App Group `group.vless.shared`
   и packet-tunnel-provider. Если Xcode ругнётся — добавьте через
   «+ Capability» в обоих таргетах; App Group должен называться ровно
   `group.vless.shared`.

## 4. Собрать и поставить на iPhone 6
- Подключите телефон (iOS 12), выберите таргет VlessApp → устройство → Run.
- При первом запуске iOS спросит разрешение на VPN-профиль → «Разрешить».
- Камера запрашивается при первом открытии QR-сканера.

## 5. Проверка
1. Добавьте сервер: «QR» / «+» (вставить ссылку) / «Подписка» / вручную.
2. Выберите сервер в списке (галочка), нажмите Connect.
3. Откройте 2ip.ru / whoer.net — должен быть IP сервера.

## Отладка, если не работает
- Логи extension: Console.app → устройство → фильтр по «VlessPacketTunnel».
- Уровень логов Xray меняется в `PacketTunnelProvider.xrayConfig()`
  (`"loglevel": "debug"`).
- Типичные причины: bundle id extension ≠ `<id приложения>.VlessPacketTunnel`,
  не совпадает App Group, сервер без поддержки UDP (тогда DNS не резолвится —
  нужен VLESS-сервер с UDP/socks-UDP).
