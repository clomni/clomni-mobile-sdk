# Clomni Example (iOS)

A ride app's profile screen with the messenger behind its own buttons: "Dəstək" (`present`), "Problem bildir"
(`startFlow` with the ride), login and logout, the unread count on the button, the optional launcher, and push with the
operator's photo ([../Examples/NotificationService](../Examples/NotificationService)). The integration code in
[ClomniExample](ClomniExample) is the one the customer documentation shows, and CI compiles it.

```sh
brew install xcodegen
cd ios/Example
xcodegen generate
open ClomniExample.xcodeproj
```

Before running: the App ID and iOS API key from Clomni (Channels → Mobile app) in `AppDelegate.swift` (or the build
settings `CLOMNI_APP_ID` and `CLOMNI_API_KEY`), and a team for signing. Push needs a real device or a Simulator on macOS 13+, and the APNs key (.p8) in the Clomni panel.

## TestFlight

[`.github/workflows/ios-testflight.yml`](../../.github/workflows/ios-testflight.yml) builds this app on a macOS runner,
signs it with an App Store Connect API key (Xcode's automatic signing, no certificates or profiles in the repository)
and uploads it to TestFlight. Version 1.0.0; the build number is the input or the run number.

**Capabilities.** The app: Push Notifications only (`aps-environment`: `development` in Debug, `production` in
Release). The Notification Service Extension: none. No App Groups, no Keychain Sharing (the SDK uses the app's own
keychain), no Associated Domains. `remote-notification` in Background Modes is an Info.plist key, nothing to enable.

**Once, on Apple's side:**

1. developer.apple.com → Certificates, IDs & Profiles → Identifiers: App ID `ai.clomni.example` with Push
   Notifications, and App ID `ai.clomni.example.NotificationService` with nothing.
2. App Store Connect → Apps → New App: iOS, name "Clomni SDK Test", bundle ID `ai.clomni.example`.
3. App Store Connect → Users and Access → Integrations → Team Keys: a key with the App Manager role. Keep the
   `.p8` (downloadable once), its Key ID and the Issuer ID. If the export step says "Cloud signing permission error",
   the key needs the Admin role.
4. Certificates, IDs & Profiles → Keys: a key with Apple Push Notifications service (APNs). Its `.p8`, Key ID and the
   Team ID go into the Clomni panel (Channels → Mobile app), production: TestFlight builds use production APNs.
5. App Store Connect → the app → TestFlight → Internal Testing: a group with the testers.

**GitHub secrets** (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8` (the whole text of `AuthKey_<id>.p8`), `CLOMNI_APP_ID`, `CLOMNI_IOS_KEY` (the demo inbox). The job runs
in the GitHub environment `dev` or `prod`: a `CLOMNI_*` pair set on an environment wins over the repository's, so a
prod build can use a prod inbox. The job stops and names any secret that is missing.

**Run:** Actions → iOS TestFlight → Run workflow, or `gh workflow run ios-testflight.yml -f environment=dev`.
`environment=dev` points the SDK at `https://dev.clomni.co/app_sdk/v1` in that build only; `prod` keeps
`https://app.clomni.ai/v1`. A build number must be higher than the last one uploaded. The build appears in TestFlight
after Apple's processing (usually 5–30 minutes). Each run makes an Apple Development certificate on the fresh runner;
old ones can be revoked under Certificates.

### TestFlight (az)

[`.github/workflows/ios-testflight.yml`](../../.github/workflows/ios-testflight.yml) bu tətbiqi macOS runner-də yığır,
App Store Connect API açarı ilə imzalayır (Xcode-un avtomatik imzası, repo-da sertifikat və profil yoxdur) və
TestFlight-a yükləyir. Versiya 1.0.0, build nömrəsi input-dan və ya run nömrəsindən.

**Capability-lər.** Tətbiq: yalnız Push Notifications (`aps-environment`: Debug-da `development`, Release-də
`production`). Notification Service Extension: heç nə. App Groups, Keychain Sharing (SDK tətbiqin öz keychain-ini
işlədir), Associated Domains yoxdur. Background Modes-dakı `remote-notification` Info.plist açarıdır, ayrıca nə isə
açmaq lazım deyil.

**Apple tərəfdə bir dəfə:**

1. developer.apple.com → Certificates, IDs & Profiles → Identifiers: `ai.clomni.example` App ID-si Push
   Notifications ilə, `ai.clomni.example.NotificationService` App ID-si capability-siz.
2. App Store Connect → Apps → New App: iOS, ad "Clomni SDK Test", bundle ID `ai.clomni.example`.
3. App Store Connect → Users and Access → Integrations → Team Keys: App Manager rolu ilə açar. `.p8` faylını (bir
   dəfə yüklənir), Key ID-ni və Issuer ID-ni saxlayın. Export addımı "Cloud signing permission error" desə, açara
   Admin rolu lazımdır.
4. Certificates, IDs & Profiles → Keys: Apple Push Notifications service (APNs) açarı. Onun `.p8`-i, Key ID-si və Team
   ID Clomni panelinə (Channels → Mobile app), production kimi: TestFlight build-ləri production APNs işlədir.
5. App Store Connect → tətbiq → TestFlight → Internal Testing: testerlərlə qrup.

**GitHub secret-ləri** (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8` (`AuthKey_<id>.p8`-in bütün mətni), `CLOMNI_APP_ID`, `CLOMNI_IOS_KEY` (demo inbox). İş `dev` və ya `prod`
GitHub environment-ində işləyir: environment-də qoyulmuş `CLOMNI_*` cütü repo-dakını əvəz edir, belə ki prod build
prod inbox-u işlədə bilər. Secret yoxdursa, iş dayanır və onun adını yazır.

**İşə salmaq:** Actions → iOS TestFlight → Run workflow, və ya `gh workflow run ios-testflight.yml -f environment=dev`.
`environment=dev` yalnız həmin build-də SDK-nı `https://dev.clomni.co/app_sdk/v1`-ə yönəldir, `prod`
`https://app.clomni.ai/v1`-də qalır. Build nömrəsi sonuncu yüklənəndən böyük olmalıdır. Build Apple emal edəndən
sonra TestFlight-da görünür (adətən 5–30 dəqiqə). Hər run təzə runner-də bir Apple Development sertifikatı yaradır,
köhnələri Certificates bölməsində ləğv etmək olar.
