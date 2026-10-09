# İstifadəçinin tanıdılması

Giriş olmadan Messenger anonim ziyarətçi üçün açılır. Ziyarətçi `logout` çağırılana qədər cihazda saxlanır, ona görə
onun söhbətləri tətbiq yenidən açılanda da qalır.

İstifadəçi tətbiqinizə daxil olanda Clomni-yə onun kim olduğunu bildirin. Onda operatorlar istifadəçinin adını,
e-poçtunu və atributlarını görür, istifadəçi hər cihazda eyni söhbətləri görür, ziyarətçinin əvvəlki söhbətləri isə
istifadəçiyə keçir.

## Necə işləyir

1. İstifadəçi tətbiqinizə daxil olur.
2. Serveriniz Identity Secret ilə istifadəçinin ID-sindən `user_hash` hesablayır və onu tətbiqə qaytarır, məsələn
   login cavabında.
3. Tətbiq istifadəçi və hash ilə `loginUser` çağırır.

Hash serverinizin bu ID-yə zəmanət verdiyini sübut edir. Onsuz istifadəçinin ID-sini bilən hər kəs öz telefonundan
həmin istifadəçinin söhbətlərini aça bilərdi.

## Düstur

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- Nəticə 64 simvoldan ibarət **kiçik hərfli** hex-dir.
- `user_id` sətirdir, tətbiqin `loginUser`-ə verdiyi ilə hərfbəhərf eyni. `12345` və `"12345"` eyni sətirdir,
  `"012345"` isə başqadır.
- Tətbiq istifadəçini `userId` olmadan daxil edirsə, hash e-poçtdan alınır: kənar boşluqlar silinmiş və kiçik
  hərflərlə.
- Dəyişməyən ID işlədin. E-poçt dəyişə bilirsə, onu ID kimi işlətməyin.

> **Diqqət.** Identity Secret heç vaxt tətbiqə düşmür: nə koda, nə `BuildConfig`-ə, nə `Info.plist`-ə, nə tətbiqlə
> gedən `.env` faylına, nə də Unity asset-lərinə. Tətbiqi açıb secret-i oxumaq olur, secret-i bilən isə istənilən
> istifadəçinin söhbətlərini aça bilər. Hash yalnız serverinizdə hesablanır.

Kodunuzu yoxlamaq üçün: `test_secret` secret-i və `12345` `user_id`-si ilə hash belədir:
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24`.

## Server kodu

Hər nümunə secret-i `CLOMNI_IDENTITY_SECRET` mühit dəyişənindən oxuyur.

### Node.js

```js
const crypto = require('crypto');

function clomniUserHash(userId) {
  return crypto
    .createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET)
    .update(String(userId))
    .digest('hex');
}

// Nümunə: hash-i öz login cavabınızla qaytarın (Express).
app.post('/api/login', async (req, res) => {
  const user = await logIn(req.body.email, req.body.password); // sizin öz login-iniz
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

`Convert.ToHexString` .NET 5 və daha yeni versiya istəyir. O, böyük hərflərlə qaytarır, ona görə
`ToLowerInvariant` lazımdır.

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

## Tətbiqdə

`loginUser`-i öz login-iniz uğurla bitəndən sonra, serverdən gələn hash ilə çağırın. İstifadəçini tanıdan sahədən
başqa bütün sahələr istəyə bağlıdır.

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

`ClomniUser`-də `phone` sahəsi də var. O, Clomni-də istifadəçinin kontaktında saxlanır.

### İstifadəçinin məlumatlarını dəyişmək

`updateUser` daxil olmuş istifadəçinin adını, dilini (`az`, `en`, `ru`) və ya fərdi atributlarını dəyişir. Yalnız
verilən sahələr dəyişir. Fərdi atributlar Clomni-dəki mövcud atributlarla birləşdirilir, operatorlar onları söhbətin
yan panelində görür.

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

## Çıxış

`logout`-u tətbiqinizin öz çıxışı ilə birlikdə çağırın. O, Clomni sessiyasını bağlayır və Messenger-in cihazdakı
məlumatlarını silir. Onsuz bu telefonda növbəti daxil olan şəxs əvvəlki istifadəçinin söhbətlərini görür.

```kotlin
Clomni.logout()          // Android və iOS
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

`logout`-dan sonra Messenger yeni anonim ziyarətçi üçün yenə işləyir.

## Rejimlər

Rejim paneldə, ayarlar sütununun **Təhlükəsizlik** bölməsində seçilir.

| Rejim | Nə baş verir |
|---|---|
| Söndürülüb | Hash yoxlanmır, istifadəçi təsdiqlənmir. Yalnız sınaq üçün. |
| Tövsiyə olunan (standart) | Göndərilən hash düzgün olmalıdır, səhv hash girişi rədd edir. Hash olmadan istifadəçi qəbul olunur, amma təsdiqlənmir. İstifadəçi bir dəfə təsdiqlənmiş hash ilə daxil olandan sonra, ondan hər dəfə hash tələb olunur. |
| Məcburi | Düzgün hash olmadan giriş yoxdur: server `403 identity_verification_failed` qaytarır. Tətbiqdən ilk təsdiqlənmiş girişdən sonra yandırmaq olar. Hash göndərməyən tətbiq versiyaları artıq qoşula bilmir. |

Yaxşı ardıcıllıq: tətbiqi `user_hash` ilə Tövsiyə olunan rejimdə buraxın, **Ümumi baxış** bölməsində hash ilə bağlı
xəbərdarlıq qalmayana qədər izləyin, sonra Məcburi rejimə keçin.

## Secret-in dəyişdirilməsi

Ayarlar sütununda **Təhlükəsizlik** → **Yeni secret yarat**. Yeni secret bir dəfə göstərilir. Köhnəsi daha 7 gün
işləyir: bu müddətdə serverinizi yeni secret-ə keçirin. **Hash-i yoxla** hash-in hansı secret ilə hazırlandığını deyir.
