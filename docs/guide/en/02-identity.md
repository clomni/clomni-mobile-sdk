# Identifying users

Without a login the Messenger opens for an anonymous visitor. The visitor is kept on the device until `logout`, so
their conversations survive app restarts.

When a user logs in to your app, tell Clomni who they are. Agents then see the user's name, e-mail and attributes,
the user sees the same conversations on every device, and the visitor's earlier conversations move to the user.

## How it works

1. The user logs in to your app.
2. Your server computes `user_hash` from the user's ID with the Identity Secret and returns it to the app, for
   example in the login response.
3. The app calls `loginUser` with the user and the hash.

The hash proves that your server vouches for this user ID. Without it anyone who knows a user ID could open that
user's conversations from their own phone.

## The formula

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- The result is 64 characters of **lower-case** hex.
- `user_id` is a string, exactly the one the app passes to `loginUser`. `12345` and `"12345"` are the same string;
  `"012345"` is a different one.
- When the app logs a user in without a `userId`, the hash is taken over the e-mail, trimmed and lower-cased.
- Use an ID that never changes. If the e-mail can change, do not use it as the ID.

> **Warning.** The Identity Secret never goes into the app: not in code, not in `BuildConfig`, not in `Info.plist`,
> not in an `.env` file shipped with the app, not in Unity assets. An app can be unpacked and the secret read out,
> and anyone with the secret can open any user's conversations. Compute the hash only on your server.

To check your code: with the secret `test_secret` and the `user_id` `12345` the hash is
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24`.

## Server code

Each example reads the secret from the environment variable `CLOMNI_IDENTITY_SECRET`.

### Node.js

```js
const crypto = require('crypto');

function clomniUserHash(userId) {
  return crypto
    .createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET)
    .update(String(userId))
    .digest('hex');
}

// Example: return the hash with your own login response (Express).
app.post('/api/login', async (req, res) => {
  const user = await logIn(req.body.email, req.body.password); // your own login
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

`Convert.ToHexString` needs .NET 5 or newer. It returns upper case, hence `ToLowerInvariant`.

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

## In the app

Call `loginUser` after your own login succeeds, with the hash from your server. Every field except the one that
identifies the user is optional.

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

`ClomniUser` also has a `phone` field, saved on the user's contact in Clomni.

### Changing the user's details

`updateUser` changes the name, the language (`az`, `en`, `ru`) or custom attributes of the logged-in user. Only the
given fields change. Custom attributes are merged with the ones Clomni already has, and agents see them in the
conversation's sidebar.

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

## Logout

Call `logout` together with your app's own logout. It ends the Clomni session and deletes the Messenger's data on the
device. Without it, the next person who logs in on this phone sees the previous user's conversations.

```kotlin
Clomni.logout()          // Android and iOS
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

After `logout` the Messenger works again for a new anonymous visitor.

## Modes

The mode is chosen under **Security** in the panel's side menu.

| Mode | What happens |
|---|---|
| Off | The hash is not checked and the user is not verified. For testing only. |
| Recommended (default) | A hash that is sent must be right; a wrong one refuses the login. Without a hash the user is accepted but not verified. Once a user has logged in with a verified hash, a hash is required for that user from then on. |
| Enforced | No login without a right hash: the server answers `403 identity_verification_failed`. It can be turned on after the first verified login from the app. App versions that send no hash can no longer connect. |

A good order: release the app with `user_hash` in Recommended mode, watch **Overview** until no warnings about
the hash are left, then switch to Enforced.

## Replacing the secret

**Security** in the side menu → **Make a new secret**. The new secret is shown once. The old one keeps working for 7 days: move your
server to the new secret within that time. **Test a hash** tells you which secret a hash was made with.
