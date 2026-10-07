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
signs it manually with an Apple Distribution certificate and two App Store profiles kept in GitHub secrets, and uploads
it to TestFlight. No Mac and no registered device are needed (automatic signing would ask for a development profile,
which needs a device); nothing secret is in the repository. Version 1.0.0; the build number is the input or the run number.

**Capabilities.** The app: Push Notifications only (`aps-environment`: `development` in Debug, `production` in
Release). The Notification Service Extension: none. No App Groups, no Keychain Sharing (the SDK uses the app's own
keychain), no Associated Domains. `remote-notification` in Background Modes is an Info.plist key, nothing to enable.

**Once, on Apple's side:**

1. developer.apple.com → Certificates, IDs & Profiles → Identifiers: App ID `ai.clomni.example` with Push
   Notifications, and App ID `ai.clomni.example.NotificationService` with nothing.
2. App Store Connect → Apps → New App: iOS, name "Clomni SDK Test", bundle ID `ai.clomni.example`.
3. App Store Connect → Users and Access → Integrations → Team Keys: a key with the Admin role (it makes the
   certificate and the profiles). Keep the `.p8` (downloadable once), its Key ID and the Issuer ID.
4. Certificates, IDs & Profiles → Keys: a key with Apple Push Notifications service (APNs). Its `.p8`, Key ID and the
   Team ID go into the Clomni panel (Channels → Mobile app), production: TestFlight builds use production APNs.
5. App Store Connect → the app → TestFlight → Internal Testing: a group with the testers.

**GitHub secrets** (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8` (the whole text of `AuthKey_<id>.p8`), `CLOMNI_APP_ID`, `CLOMNI_IOS_KEY` (the demo inbox), and
`GH_SECRETS_TOKEN`: a fine-grained token for this repository with Secrets: write. The job runs in the GitHub
environment `dev` or `prod`: a `CLOMNI_*` pair set on an environment wins over the repository's, so a prod build can
use a prod inbox. The job stops and names any secret that is missing.

**Signing, once:** Actions → iOS signing setup → Run workflow (`gh workflow run ios-signing-setup.yml`). With the API
key it makes an Apple Distribution certificate and the App Store profiles "Clomni Example AppStore" and "Clomni
Example NSE AppStore", and writes `IOS_DIST_P12`, `IOS_DIST_P12_PASSWORD`, `IOS_PROFILE_APP`, `IOS_PROFILE_NSE`,
`IOS_PROFILE_APP_NAME`, `IOS_PROFILE_NSE_NAME`. A team holds only 2–3 distribution certificates; if Apple refuses a new
one, the run lists them, and `revoke_old=true` revokes them all first, including any used elsewhere (EAS, Xcode).
Run it again when the certificate or a profile expires (a year), after a revoke, or when an App ID's capabilities
change. In `project.yml` the Release configuration of both targets is manual (`Apple Distribution`, the profile names
from the workflow); Debug stays automatic, so a local Release or Archive needs these profiles.

**Run:** Actions → iOS TestFlight → Run workflow, or `gh workflow run ios-testflight.yml -f environment=dev`.
`environment=dev` points the SDK at `https://dev.clomni.co/app_sdk/v1` in that build only; `prod` keeps
`https://app.clomni.ai/v1`. A build number must be higher than the last one uploaded. The build appears in TestFlight
after Apple's processing (usually 5–30 minutes). Each run imports the certificate into a keychain of its own and
deletes it, the profiles and the API key at the end.

### TestFlight (az)

[`.github/workflows/ios-testflight.yml`](../../.github/workflows/ios-testflight.yml) bu tətbiqi macOS runner-də yığır,
GitHub secret-lərində saxlanan Apple Distribution sertifikatı və iki App Store profili ilə əl ilə (manual) imzalayır və
TestFlight-a yükləyir. Mac və qeydiyyatlı cihaz lazım deyil (avtomatik imza development profili istəyir, o isə cihaz
tələb edir); repo-da heç bir sirr yoxdur. Versiya 1.0.0, build nömrəsi input-dan və ya run nömrəsindən.

**Capability-lər.** Tətbiq: yalnız Push Notifications (`aps-environment`: Debug-da `development`, Release-də
`production`). Notification Service Extension: heç nə. App Groups, Keychain Sharing (SDK tətbiqin öz keychain-ini
işlədir), Associated Domains yoxdur. Background Modes-dakı `remote-notification` Info.plist açarıdır, ayrıca nə isə
açmaq lazım deyil.

**Apple tərəfdə bir dəfə:**

1. developer.apple.com → Certificates, IDs & Profiles → Identifiers: `ai.clomni.example` App ID-si Push
   Notifications ilə, `ai.clomni.example.NotificationService` App ID-si capability-siz.
2. App Store Connect → Apps → New App: iOS, ad "Clomni SDK Test", bundle ID `ai.clomni.example`.
3. App Store Connect → Users and Access → Integrations → Team Keys: Admin rolu ilə açar (sertifikatı və profilləri o
   yaradır). `.p8` faylını (bir dəfə yüklənir), Key ID-ni və Issuer ID-ni saxlayın.
4. Certificates, IDs & Profiles → Keys: Apple Push Notifications service (APNs) açarı. Onun `.p8`-i, Key ID-si və Team
   ID Clomni panelinə (Channels → Mobile app), production kimi: TestFlight build-ləri production APNs işlədir.
5. App Store Connect → tətbiq → TestFlight → Internal Testing: testerlərlə qrup.

**GitHub secret-ləri** (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8` (`AuthKey_<id>.p8`-in bütün mətni), `CLOMNI_APP_ID`, `CLOMNI_IOS_KEY` (demo inbox) və `GH_SECRETS_TOKEN`:
bu repo üçün "Secrets: write" icazəli fine-grained token. İş `dev` və ya `prod` GitHub environment-ində işləyir:
environment-də qoyulmuş `CLOMNI_*` cütü repo-dakını əvəz edir, belə ki prod build prod inbox-u işlədə bilər. Secret
yoxdursa, iş dayanır və onun adını yazır.

**İmza, bir dəfə:** Actions → iOS signing setup → Run workflow (`gh workflow run ios-signing-setup.yml`). API açarı
ilə Apple Distribution sertifikatı və "Clomni Example AppStore", "Clomni Example NSE AppStore" App Store profillərini
yaradır, `IOS_DIST_P12`, `IOS_DIST_P12_PASSWORD`, `IOS_PROFILE_APP`, `IOS_PROFILE_NSE`, `IOS_PROFILE_APP_NAME`,
`IOS_PROFILE_NSE_NAME` secret-lərini yazır. Komandada cəmi 2–3 distribution sertifikatı ola bilər; Apple yenisini
rədd etsə, iş mövcudları siyahı ilə göstərir, `revoke_old=true` isə əvvəlcə hamısını ləğv edir, başqa yerdə (EAS,
Xcode) işlənəni də. Sertifikatın və ya profilin vaxtı bitəndə (bir il), ləğvdən sonra və ya App ID-nin capability-ləri
dəyişəndə yenidən işə salın. `project.yml`-də hər iki hədəfin Release konfiqurasiyası manualdır (`Apple Distribution`,
profil adları workflow-dan); Debug avtomatik qalır, ona görə lokal Release və ya Archive üçün bu profillər lazımdır.

**İşə salmaq:** Actions → iOS TestFlight → Run workflow, və ya `gh workflow run ios-testflight.yml -f environment=dev`.
`environment=dev` yalnız həmin build-də SDK-nı `https://dev.clomni.co/app_sdk/v1`-ə yönəldir, `prod`
`https://app.clomni.ai/v1`-də qalır. Build nömrəsi sonuncu yüklənəndən böyük olmalıdır. Build Apple emal edəndən
sonra TestFlight-da görünür (adətən 5–30 dəqiqə). Hər run sertifikatı öz müvəqqəti keychain-inə idxal edir, sonda
onu, profilləri və API açarını silir.
