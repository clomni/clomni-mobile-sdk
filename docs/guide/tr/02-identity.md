# Kullanıcıların tanınması

Oturum açılmadan Messenger anonim bir ziyaretçi için açılır. Ziyaretçi `logout` çağrılana kadar cihazda saklanır;
bu sayede konuşmaları uygulama yeniden başlatıldığında kaybolmaz.

Kullanıcı uygulamanızda oturum açtığında bunu Clomni'ye bildirin. Böylece temsilciler kullanıcının adını, e-postasını
ve özniteliklerini görür, kullanıcı her cihazda aynı konuşmaları görür ve ziyaretçinin önceki konuşmaları kullanıcıya
taşınır.

## Nasıl çalışır

1. Kullanıcı uygulamanızda oturum açar.
2. Sunucunuz, kullanıcının kimliğinden Identity Secret ile `user_hash` hesaplar ve uygulamaya döndürür, örneğin
   oturum açma yanıtının içinde.
3. Uygulama, kullanıcı ve hash ile `loginUser` çağırır.

Hash, sunucunuzun bu kullanıcı kimliğine kefil olduğunu kanıtlar. Hash olmasaydı, bir kullanıcı kimliğini bilen
herkes o kullanıcının konuşmalarını kendi telefonundan açabilirdi.

## Formül

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- Sonuç, **küçük harfli** 64 karakterlik bir hex dizesidir.
- `user_id` bir dizedir ve uygulamanın `loginUser`'a verdiğiyle birebir aynı olmalıdır. `12345` ve `"12345"` aynı
  dizedir; `"012345"` ise farklıdır.
- Uygulama kullanıcıyı `userId` olmadan oturuma alırsa hash, boşlukları kırpılmış ve küçük harfe çevrilmiş e-posta
  üzerinden hesaplanır.
- Hiç değişmeyen bir kimlik kullanın. E-posta değişebiliyorsa onu kimlik olarak kullanmayın.

> **Uyarı.** Identity Secret asla uygulamaya girmez: ne kodda, ne `BuildConfig`'te, ne `Info.plist`'te, ne
> uygulamayla birlikte dağıtılan bir `.env` dosyasında, ne de Unity asset'lerinde. Bir uygulama açılıp secret
> okunabilir; secret'a sahip olan herkes de herhangi bir kullanıcının konuşmalarını açabilir. Hash'i yalnızca
> sunucunuzda hesaplayın.

Kodunuzu kontrol etmek için: `test_secret` secret'ı ve `12345` `user_id`'si ile hash şudur:
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24`.

## Sunucu kodu

Her örnek secret'ı `CLOMNI_IDENTITY_SECRET` ortam değişkeninden okur.

### Node.js

```js
const crypto = require('crypto');

function clomniUserHash(userId) {
  return crypto
    .createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET)
    .update(String(userId))
    .digest('hex');
}

// Örnek: hash'i kendi oturum açma yanıtınızla birlikte döndürün (Express).
app.post('/api/login', async (req, res) => {
  const user = await logIn(req.body.email, req.body.password); // sizin oturum açma kodunuz
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

`Convert.ToHexString` .NET 5 veya daha yenisini gerektirir. Büyük harf döndürdüğü için `ToLowerInvariant` gerekir.

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

## Uygulamada

Kendi oturum açma işleminiz başarılı olduktan sonra, sunucunuzdan gelen hash ile `loginUser` çağırın. Kullanıcıyı
tanımlayan alan dışındaki tüm alanlar isteğe bağlıdır.

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

`ClomniUser` ayrıca bir `phone` alanına sahiptir; bu alan Clomni'de kullanıcının kişi kaydına yazılır.

### Kullanıcı bilgilerini değiştirme

`updateUser`, oturum açmış kullanıcının adını, dilini (`az`, `en`, `ru`) veya özel özniteliklerini değiştirir.
Yalnızca verilen alanlar değişir. Özel öznitelikler Clomni'de zaten bulunanlarla birleştirilir ve temsilciler bunları
konuşmanın kenar çubuğunda görür.

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

## Oturumu kapatma

`logout`'u uygulamanızın kendi oturum kapatma işlemiyle birlikte çağırın. Clomni oturumunu sonlandırır ve
Messenger'ın cihazdaki verilerini siler. Çağrılmazsa bu telefonda oturum açan bir sonraki kişi önceki kullanıcının
konuşmalarını görür.

```kotlin
Clomni.logout()          // Android ve iOS
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

`logout`'tan sonra Messenger yeni bir anonim ziyaretçi için yeniden çalışır.

## Modlar

Mod, panelin soldaki menüsünde **Security** bölümünde seçilir.

| Mod | Ne olur |
|---|---|
| Off | Hash kontrol edilmez, kullanıcı doğrulanmaz. Yalnızca test için. |
| Recommended (varsayılan) | Gönderilen hash doğru olmalıdır; yanlış hash oturum açmayı reddeder. Hash yoksa kullanıcı kabul edilir ama doğrulanmış sayılmaz. Bir kullanıcı doğrulanmış bir hash ile oturum açtıktan sonra, o kullanıcı için bundan sonra hash zorunludur. |
| Enforced | Doğru hash olmadan oturum açılamaz: sunucu `403 identity_verification_failed` yanıtını verir. Uygulamadan ilk doğrulanmış oturum açmadan sonra açılabilir. Hash göndermeyen uygulama sürümleri artık bağlanamaz. |

Önerilen sıra: uygulamayı `user_hash` ile Recommended modda yayınlayın, **Overview**'da hash ile ilgili uyarı
kalmayana kadar takip edin, ardından Enforced'a geçin.

## Secret'ı değiştirme

Soldaki menüde **Security** → **Make a new secret**. Yeni secret bir kez gösterilir. Eskisi 7 gün daha çalışır:
sunucunuzu bu süre içinde yeni secret'a geçirin. **Test a hash**, bir hash'in hangi secret ile üretildiğini söyler.
