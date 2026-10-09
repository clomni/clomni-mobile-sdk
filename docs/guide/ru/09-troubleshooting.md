# Решение проблем

## С чего начать

1. **Раздел Overview в панели.** Он показывает, подключилась ли каждая платформа, включены ли push-уведомления, и
   предупреждения вроде «входы отклонены из-за неверного хеша» или «push не настроен» — у каждого есть кнопка
   **Fix**.
2. **Лог SDK.** По умолчанию уровень `warning`: предупреждения и ошибки пишутся всегда, ошибки интеграции (ключи,
   хеш, push) пишутся как `error`. На время разработки включите уровень `debug`: он дополнительно пишет шаги SDK.

| Платформа | Как включить | Где лог |
|---|---|---|
| Android | `Clomni.setLogLevel(ClomniLogLevel.DEBUG)` | logcat, тег `Clomni` |
| iOS | `Clomni.setLogLevel(.debug)` | Консоль Xcode и Console.app: subsystem `ai.clomni.messenger`, category `Clomni` |
| React Native | `Clomni.setLogLevel('debug')` | нативные логи, указанные выше |
| Flutter | `await Clomni.setLogLevel(ClomniLogLevel.debug)` | нативные логи, указанные выше; ошибки на стороне Dart начинаются с `[Clomni]` |
| Unity | `Clomni.SetLogLevel(ClomniLogLevel.Debug)` | нативные логи, указанные выше |

Некоторые сообщения сервера приходят на азербайджанском — в таблице ниже они приведены в точности так, как
выглядят.

## Настройка

| Лог или симптом | Причина | Что делать |
|---|---|---|
| `call Clomni.initialize first` | Метод вызван до `initialize` | Вызывайте `initialize` при запуске; на Android — в `Application.onCreate` |
| `initialize was called before; the first call stays` | `initialize` вызван дважды | Вызывайте один раз. Чтобы сменить ключи, перезапустите приложение |
| `api_key səhvdir və ya bu platforma üçün deyil` | API-ключ неверный, отозван, с момента создания нового прошло больше 7 дней или это ключ другой платформы | На Android — ключ `android_…`, на iOS — `ios_…`. Проверьте ключ в разделе **Installation** |
| Android 1.0.1+: `api_key səhvdir ... Tətbiqin paket adı: …` | Имя пакета приложения (с `applicationIdSuffix`) не совпадает с именем пакета Android в канале | Сравните имя пакета в логе с тем, что в панели, см. [Версии](10-versions.md) |
| `this App SDK inbox is switched off in Clomni` | Канал выключен в панели | Включите его. До этого `present()` ничего не делает |
| Ничего не открывается, в логе пусто | Слишком низкий уровень лога или вызов в Unity Editor | Включите уровень debug; проверяйте на устройстве |
| `setTheme: primaryColor "…" is not #RRGGBB` | Формат цвета | Шесть hex-цифр с `#`, например `#0A66C2` |
| iOS: `no window to present the messenger from yet` | `present` вызван, когда экрана ещё нет | Вызывайте из кнопки или после показа экрана |
| iOS: `font family "…" is not in the app; the system font stays` | Шрифта нет в бандле | Добавьте его в таргет и в `UIAppFonts` |
| Приложение не может достучаться до сервера в корпоративной сети | Хост блокирует прокси или список разрешённых | Разрешите `app.clomni.ai` (HTTPS и WebSocket) |

## Пользователи

| Лог или симптом | Причина | Что делать |
|---|---|---|
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | Хеш не совпадает | Та же строка `user_id`, что в `loginUser`, hex в нижнем регистре, текущий secret. Без `userId` — e-mail без пробелов по краям и в нижнем регистре. Проверьте через Security → Test a hash |
| `403 identity_verification_failed` | Режим Enforced, а хеша нет или он неверный | Передавайте хеш или вернитесь на Recommended, пока его не будут передавать все версии приложения |
| Следующий пользователь телефона видит диалоги предыдущего | Не вызывается `logout` | Вызывайте `Clomni.logout()` вместе с выходом из вашего приложения |
| Операторы не видят имя или e-mail пользователя | `loginUser` вызывается без них или до завершения вашего входа | Передавайте поля; для последующих изменений используйте `updateUser` |

## Сценарии, оформление и тексты

| Симптом | Причина | Что делать |
|---|---|---|
| `startFlow` ничего не делает | К событию не привязан опубликованный сценарий | В конструкторе сценариев: триггер «App event», то же имя, сценарий опубликован. Раздел **Flows** показывает имя события |
| `{{data.…}}` в тексте сценария остаётся пустым | Ключ в данных `startFlow` называется иначе | Используйте один и тот же ключ в приложении и в сценарии |
| Изменение в панели не видно в приложении | Черновик Appearance не опубликован | Appearance → **Publish** |
| Messenger говорит не на том языке | `setLanguage` выбрал выключенный язык или язык не выбран | Включите язык в Appearance → Languages или вызовите `setLanguage` |
| Плавающая кнопка не появляется | Она выключена и в панели, и в коде | `setLauncherVisible(true)` или включите в Appearance → Theme |
| React Native: плавающая кнопка не появляется при холодном запуске | Ошибка SDK 1.0.1 | Исправлено в SDK 1.0.2. До этого открывайте Messenger своей кнопкой |
| React Native, Android: открытый Messenger пропадает, когда приложение снова открывают по иконке | `MainActivity` с `singleTask` | Исправлено в SDK 1.0.2 |
| Flutter, Android: плавающая кнопка не появляется | `MainActivity` наследует `FlutterActivity` | Наследуйте `FlutterFragmentActivity` |

## Push-уведомления

Начните с **Push** в колонке настроек → **Test push**. Ответ там — это ответ самого FCM или APNs, а таблица в главе
[Ключи для push](08-push-keys.md#test-push) объясняет каждый ответ.

| Симптом | Причина | Что делать |
|---|---|---|
| Устройства нет в списке Test push | До Clomni не дошёл ни один токен | Разрешите уведомления на телефоне; проверьте вызов `setDeviceToken`; один раз откройте Messenger |
| Android: уведомления нет, `notification not shown (POST_NOTIFICATIONS?)` | Нет разрешения на Android 13+ | Запросите `POST_NOTIFICATIONS` |
| Android: `push token not registered: …` | Токен не дошёл до сервера | Проверьте сеть и вызов `setDeviceToken` |
| Android: уведомления приходят, только когда приложение открыто | Data-сообщение обрабатывается только в UI | Передавайте сообщение в `ClomniPush.handle` в `FirebaseMessagingService` (React Native: `setBackgroundMessageHandler`, Flutter: `onBackgroundMessage`) |
| Android: серый квадрат вместо иконки | Иконка приложения не силуэт | `setNotificationIcon` с белой иконкой |
| Android: `SENDER_ID_MISMATCH` | Service account и `google-services.json` из разных проектов Firebase | Загрузите service account проекта приложения |
| iOS: `BadEnvironmentKeyInToken` | Ключ APNs ограничен одним окружением | Создайте ключ для Sandbox & Production |
| iOS: `InvalidProviderToken` | Неверный Key ID или Team ID, или ключ отозван | Проверьте оба идентификатора; загрузите ключ заново |
| iOS: `DeviceTokenNotForTopic` | Bundle ID в разделе **Push** не совпадает с приложением | Укажите Bundle ID приложения |
| iOS: работает из Xcode, но не из TestFlight (или наоборот) | Ключ покрывает только одно окружение | Ключ Sandbox & Production |
| iOS: нажатие на уведомление Clomni только открывает приложение | Нажатие не доходит до `handlePush` | Нативный iOS: делегат в AppDelegate. React Native и Flutter: нативный делегат из их глав; библиотеки Firebase не видят push от Clomni на iOS |
| iOS: приложение падает при нажатии с «Call must be made on main thread» | Асинхронный метод делегата помечен `nonisolated` | Пометьте его `@MainActor` |
| Уведомление Clomni появляется при открытом Messenger | Не используется `shouldShowForeground` | Если он вернул false, не возвращайте вариантов показа |

## Ключи после замены

- Новый API-ключ: старый работает ещё 7 дней. После этого версии приложения со старым ключом не смогут
  подключиться.
- Отозванный API-ключ перестаёт работать сразу.
- Новый Identity Secret: старый работает ещё 7 дней. Test a hash показывает, каким secret был сделан хеш.
- Новый ключ для push: загрузите его в разделе **Push**; следующий push будет отправлен с ним.

## Как обратиться за помощью

Напишите в поддержку Clomni и укажите:

- платформу и версию SDK (`Clomni.version` в Kotlin и Swift);
- App ID (но никогда не Identity Secret и не полный API-ключ);
- что показывает **Overview**, и лог SDK на уровне debug в момент проблемы;
- для push: ответ Test push.
