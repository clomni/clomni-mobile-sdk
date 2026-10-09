# Ключи для push

Clomni отправляет push-уведомления с вашими собственными ключами: service account Firebase для Android и ключом APNs
для iOS. Оба загружаются в разделе **Push** колонки настроек канала (или на 4-м шаге мастера).

| Платформа | Что нужно панели | Откуда взять |
|---|---|---|
| Android | Service account JSON | Firebase console → Project settings → Service accounts |
| iOS | Ключ `.p8`, Key ID, Team ID, Bundle ID | Apple Developer → Certificates, Identifiers & Profiles → Keys |

## Android: service account JSON из Firebase

> Панели нужен **service account JSON**, а не `google-services.json`. `google-services.json` кладётся в приложение и
> лишь указывает проект. Service account JSON — это закрытый ключ, с которым сервер Clomni может отправлять
> сообщения через ваш проект.

1. Откройте [Firebase console](https://console.firebase.google.com) и выберите проект, к которому относится
   `google-services.json` вашего приложения. Push работает, только если оба файла из одного проекта.
2. Нажмите на шестерёнку рядом с «Project Overview» → **Project settings** → вкладка **Service accounts**.
3. В блоке «Firebase Admin SDK» нажмите **Generate new private key**, затем **Generate key**. Скачается JSON-файл.

   > **Путь:** `Firebase console → ⚙ Project settings → Service accounts → Firebase Admin SDK → Generate new private key → Generate key`
   >
   > Документация: [firebase.google.com/docs/admin/setup](https://firebase.google.com/docs/admin/setup#initialize-sdk-non-google)

4. В панели Clomni: канал → **Push** → «Android · Firebase Cloud Messaging» → **Service account JSON file** (1) и
   выберите скачанный файл. После этого в карточке появятся название проекта и дата загрузки.

   ![Панель Clomni: загрузка service account JSON](../images/panel-push-fcm-en.png)

Храните файл как пароль: не коммитьте его и не отправляйте по почте. Если он утёк, удалите ключ в Google Cloud
Console (IAM → Service accounts → Keys) и загрузите новый.

Firebase Cloud Messaging API (V1) в новых проектах Firebase включён по умолчанию. Если его отключили, Test push
покажет ошибку от FCM; включите API в Google Cloud Console → APIs & Services.

## iOS: ключ APNs

Нужна роль Account Holder или Admin в Apple Developer Program.

### 1. Создайте ключ

1. Откройте [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers &
   Profiles** → **Keys** → **+**.

   > **Путь:** `developer.apple.com/account → Certificates, Identifiers & Profiles → Keys → +`
   >
   > Кнопка **+** находится рядом с заголовком **Keys**.
   >
   > Документация: [developer.apple.com/help/account/keys/create-a-private-key](https://developer.apple.com/help/account/keys/create-a-private-key/)

2. Назовите ключ, отметьте **Apple Push Notifications service (APNs)** и нажмите **Configure**.
3. **Environment: Sandbox & Production.** Этот выбор важен:
   - Ключ только для Sandbox работает в сборках, запущенных из Xcode, но не работает в TestFlight и App Store.
   - Ключ только для Production работает в TestFlight и App Store, но не работает в сборках, запущенных из Xcode.
   - В обоих случаях APNs отвечает `BadEnvironmentKeyInToken`, и push не доходит.

   В ограничениях ключа вариант **Team Scoped (All Topics)** позволяет одному ключу обслуживать все приложения
   вашей команды.

   > **Путь:** `Keys → + → Key Name → Apple Push Notifications service (APNs) → Configure`
   >
   > Выберите **Environment: Sandbox & Production** и **Key Restriction: Team Scoped (All Topics)**, затем **Save**.
   >
   > Документация: [developer.apple.com/help/account/keys/create-a-private-key](https://developer.apple.com/help/account/keys/create-a-private-key/)

4. **Save** → **Continue** → **Register**.

Ключи, созданные до того, как Apple добавила выбор окружения, работают в обоих окружениях. Если у вашей команды уже
есть такой ключ или ключ Sandbox & Production, его можно использовать и для Clomni.

### 2. Скачайте ключ и запишите идентификаторы

1. На странице ключа нажмите **Download**. Файл `.p8` можно скачать **только один раз**. Храните его надёжно; если
   он потерян, создайте новый ключ.
2. Запишите **Key ID** с той же страницы (10 символов).

   > **Путь:** `Certificates, Identifiers & Profiles → Keys → ваш ключ → Download`
   >
   > **Key ID** указан под названием ключа. **Download** — в правом верхнем углу страницы.
   >
   > Документация: [developer.apple.com/help/account/keys/get-a-key-identifier](https://developer.apple.com/help/account/keys/get-a-key-identifier/), [developer.apple.com/help/account/keys/revoke-edit-and-download-keys](https://developer.apple.com/help/account/keys/revoke-edit-and-download-keys/)

3. Найдите **Team ID**: Apple Developer → **Membership details** (10 символов).

   > **Путь:** `developer.apple.com/account → Membership details → Team ID`
   >
   > Документация: [developer.apple.com/help/account/basics/account-landing-page](https://developer.apple.com/help/account/basics/account-landing-page/)

4. **Bundle ID** — это Bundle Identifier вашего приложения (Xcode → таргет → Signing & Capabilities), например
   `com.example.app`.

### 3. Загрузите ключ в Clomni

Канал → **Push** → «iOS · Apple Push Notification service»:

![Панель Clomni: загрузка ключа APNs](../images/panel-push-apns-en.png)

1. **.p8 file**: выберите скачанный `AuthKey_XXXXXXXXXX.p8`.
2. **Key ID**.
3. **Team ID**.
4. **Bundle ID**.
5. **Upload**.

Панель проверяет форматы (Key ID и Team ID — 10 букв или цифр). Примет ли Apple ключ, станет понятно при первом
push: воспользуйтесь Test push.

## Test push

Когда приложение запущено на телефоне с разрешёнными уведомлениями и передало токен, устройство появляется в списке
**Test push** в разделе **Push**. Выберите его и нажмите **Send**. Ответ — это ответ самого FCM или APNs.

| Ответ | Что значит | Что делать |
|---|---|---|
| Sent | Уведомление отправлено | Если ничего не появилось, проверьте push-код приложения |
| `BadEnvironmentKeyInToken` (APNs) | Ключ ограничен другим окружением | Создайте ключ Sandbox & Production |
| `InvalidProviderToken` (APNs) | Неверный Key ID или Team ID, или ключ отозван | Проверьте оба идентификатора; загрузите ключ заново |
| `DeviceTokenNotForTopic` (APNs) | Bundle ID не совпадает с приложением | Укажите Bundle ID приложения |
| `BadDeviceToken` (APNs) | Токен от другого приложения или уже недействителен | Переустановите приложение, откройте его, разрешите уведомления |
| `SENDER_ID_MISMATCH` (FCM) | Service account из другого проекта Firebase, чем `google-services.json` | Загрузите service account проекта приложения |
| `UNREGISTERED` (FCM) | Приложение удалено с устройства или токен истёк | Откройте приложение снова, чтобы оно отправило новый токен |
| Not sent: no key | Для этой платформы ключ не загружен | Загрузите ключ |

Токен, который APNs или FCM считают недействительным, Clomni удаляет. Их число показывает столбец «Removed tokens» в
разделе **Push**.
