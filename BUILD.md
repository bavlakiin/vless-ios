# Быстрая сборка на Маке (порядок строго такой)

## 0. Что нужно
- macOS с Xcode (для iOS 12-устройства — Xcode 10.3 на Mojave; на новом Xcode сборка тоже работает, но установка на iOS 12 может потребовать старого Xcode)
- Apple Developer-аккаунт (платный — NetworkExtension без него не подписать)
- Go 1.20.x (`brew install go@1.20`), XcodeGen (`brew install xcodegen`)

## 1. Собрать ядро (5–10 минут)
```bash
cd vless-ios
./scripts/build-core.sh
```
Появится `XrayFramework/VlessCore.xcframework` (Xray-core + tun2socks).

## 2. Сгенерировать Xcode-проект
```bash
brew install xcodegen   # если ещё нет
xcodegen
open VlessApp.xcodeproj
```

## 3. Один раз настроить в Xcode
1. В обоих таргетах (VlessApp и VlessPacketTunnel) → Signing & Capabilities:
   выберите свою команду (Team). В `project.yml` замените `REPLACE_WITH_YOUR_TEAM_ID`.
2. Capabilities уже прописаны в entitlements: App Group `group.vless.shared`
   и Network Extension. Если Xcode ругнётся — добавьте их через
   «+ Capability» в обоих таргетах, App Group должен называться ровно
   `group.vless.shared`.

## 4. Собрать и поставить на iPhone 6
- Подключите телефон, выберите таргет VlessApp → ваше устройство → Run.
- При первом запуске iOS спросит разрешение на VPN-профиль → «Разрешить».
- На iOS 12 в Настройках появится VPN «VLESS».

## 5. Проверка
1. Вставьте ссылку `vless://...` в поле → Import profile.
2. Нажмите Connect. Статус должен стать `connected`.
3. Откройте 2ip.ru / whoer.net — должен быть IP сервера.

## Отладка, если не работает
- Логи extension: Console.app → выберите телефон → фильтр по «VlessPacketTunnel».
- Xray пишет в loglevel warning; поднимите до "debug" в `xrayConfig()`.
- Чаще всего ломается на: неверный bundle id extension (должен быть
  `<id приложения>.VlessPacketTunnel`), не совпадающий App Group,
  или протухший REALITY public key.
