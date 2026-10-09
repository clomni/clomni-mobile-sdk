# Идентификация пользователей

Без входа Messenger открывается для анонимного посетителя. Посетитель хранится на устройстве до вызова `logout`,
поэтому его диалоги не теряются при перезапуске приложения.

Когда пользователь входит в ваше приложение, сообщите Clomni, кто он. Тогда операторы видят имя, e-mail и атрибуты
пользователя, сам пользователь видит одни и те же диалоги на всех устройствах, а прежние диалоги посетителя
переходят к пользователю.

## Как это работает

1. Пользователь входит в ваше приложение.
2. Ваш сервер вычисляет `user_hash` из ID пользователя с помощью Identity Secret и возвращает его приложению,
   например в ответе на запрос входа.
3. Приложение вызывает `loginUser` с пользователем и хешем.

Хеш подтверждает, что ваш сервер ручается за этот ID пользователя. Без него любой, кто знает чей-то ID, мог бы
открыть диалоги этого пользователя со своего телефона.

## Формула

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- Результат — 64 символа hex в **нижнем регистре**.
- `user_id` — строка, ровно та же, что приложение передаёт в `loginUser`. `12345` и `"12345"` — одна и та же
  строка, а `"012345"` — уже другая.
- Если приложение авторизует пользователя без `userId`, хеш берётся от e-mail без пробелов по краям и в нижнем
  регистре.
- Используйте ID, который никогда не меняется. Если e-mail может измениться, не используйте его в качестве ID.

> **Внимание.** Identity Secret никогда не попадает в приложение: ни в код, ни в `BuildConfig`, ни в `Info.plist`,
> ни в поставляемый с приложением `.env`, ни в ассеты Unity. Приложение можно распаковать и достать из него secret,
> а с secret можно открыть диалоги любого пользователя. Вычисляйте хеш только на сервере.

Для проверки кода: при secret `test_secret` и `user_id` `12345` хеш равен
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24`.

## Код для сервера

Во всех примерах secret читается из переменной окружения `CLOMNI_IDENTITY_SECRET`.

### Node.js

```js
const crypto = require('crypto');

function clomniUserHash(userId) {
  return crypto
    .createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET)
    .update(String(userId))
    .digest('hex');
}

// Пример: верните хеш в ответе вашего собственного входа (Express).
app.post('/api/login', async (req, res) => {
  const user = await logIn(req.body.email, req.body.password); // ваш собственный вход
  res.json({ user, clomniUserHash: clomniUserHash(user.id) });
});
```

### PHP

```php
<?php

function clomni_user_hash(string $userId): string
{
    return hash_hmac('sha256', $userId, getenv('CLOMNI_IDENTITY_SECRET'));
}
```

### Python

```python
import hashlib
import hmac
import os


def clomni_user_hash(user_id) -> str:
    secret = os.environ["CLOMNI_IDENTITY_SECRET"].encode()
    return hmac.new(secret, str(user_id).encode(), hashlib.sha256).hexdigest()
```

### Ruby

```ruby
require 'openssl'

def clomni_user_hash(user_id)
  OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('CLOMNI_IDENTITY_SECRET'), user_id.to_s)
end
```

### Java

```java
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class ClomniUserHash {
    private ClomniUserHash() {}

    public static String of(String userId) throws GeneralSecurityException {
        String secret = System.getenv("CLOMNI_IDENTITY_SECRET");
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        byte[] digest = mac.doFinal(userId.getBytes(StandardCharsets.UTF_8));
        StringBuilder hex = new StringBuilder(digest.length * 2);
        for (byte b : digest) {
            hex.append(String.format("%02x", b));
        }
        return hex.toString();
    }
}
```

### C#

```csharp
using System;
using System.Security.Cryptography;
using System.Text;

public static class ClomniUserHash
{
    public static string Of(string userId)
    {
        var secret = Environment.GetEnvironmentVariable("CLOMNI_IDENTITY_SECRET")!;
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var digest = hmac.ComputeHash(Encoding.UTF8.GetBytes(userId));
        return Convert.ToHexString(digest).ToLowerInvariant();
    }
}
```

`Convert.ToHexString` требует .NET 5 или новее. Метод возвращает верхний регистр, отсюда `ToLowerInvariant`.

### Go

```go
package clomni

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"os"
)

// UserHash is the user_hash Clomni expects for userID.
func UserHash(userID string) string {
	mac := hmac.New(sha256.New, []byte(os.Getenv("CLOMNI_IDENTITY_SECRET")))
	mac.Write([]byte(userID))
	return hex.EncodeToString(mac.Sum(nil))
}
```

## В приложении

Вызывайте `loginUser` после успешного входа в ваше приложение, с хешем от вашего сервера. Все поля, кроме
идентифицирующего пользователя, необязательны.

```kotlin
// Android
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = hashFromYourServer)
```

```swift
// iOS
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: hashFromYourServer)
```

```ts
// React Native
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, hashFromYourServer);
```

```dart
// Flutter
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: hashFromYourServer,
);
```

```csharp
// Unity
Clomni.LoginUser(new ClomniUser { UserId = "12345", Email = "aysel@example.com", Name = "Aysel Məmmədova" },
    hashFromYourServer);
```

У `ClomniUser` есть и поле `phone`, оно сохраняется в контакте пользователя в Clomni.

### Изменение данных пользователя

`updateUser` меняет имя, язык (`az`, `en`, `ru`) или пользовательские атрибуты вошедшего пользователя. Меняются
только переданные поля. Пользовательские атрибуты объединяются с теми, что уже есть в Clomni, и операторы видят их на
боковой панели диалога.

```kotlin
Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))
```

```swift
Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])
```

```ts
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });
```

```dart
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});
```

```csharp
Clomni.UpdateUser(language: "az", customAttributes: new Dictionary<string, object> { ["plan"] = "premium" });
```

## Выход

Вызывайте `logout` вместе с выходом из вашего приложения. Он завершает сессию Clomni и удаляет данные Messenger на
устройстве. Без него следующий человек, вошедший на этом телефоне, увидит диалоги предыдущего пользователя.

```kotlin
Clomni.logout()          // Android и iOS
```

```ts
Clomni.logout();         // React Native
```

```dart
await Clomni.logout();   // Flutter
```

```csharp
Clomni.Logout();         // Unity
```

После `logout` Messenger снова работает для нового анонимного посетителя.

## Режимы

Режим выбирается в колонке настроек канала, в разделе **Security**.

| Режим | Что происходит |
|---|---|
| Off | Хеш не проверяется: принимается любой хеш, пользователь не верифицирован. Любой, кто передаст приложению чужой `user_id`, может открыть чужие диалоги. Только для тестов. |
| Recommended (по умолчанию) | Если хеш передан, он должен быть верным: с неверным хешем вход отклоняется. Без хеша пользователь принимается, но не считается верифицированным. После первого входа пользователя с верифицированным хешем хеш для него становится обязательным. |
| Enforced | Без верного хеша входа нет: сервер отвечает `403 identity_verification_failed`. Режим можно включить после первого верифицированного входа из приложения. Версии приложения, которые не передают хеш, больше не смогут подключиться. |

> **Никогда не используйте Off в рабочем приложении.** В этом режиме принимается любой хеш.

Хороший порядок: выпустите приложение с `user_hash` в режиме Recommended, следите за **Overview**, пока не исчезнут
предупреждения о хеше, затем переключитесь на Enforced.

## Замена secret

**Security** в колонке настроек → **Make a new secret**. Новый secret показывается один раз. Старый работает ещё 7 дней:
за это время переведите сервер на новый. **Test a hash** показывает, каким secret был сделан хеш.
