# Clomni Mobile SDK guide

The integration guide for app developers, step by step and with screenshots.

- English: [en/00-overview.md](en/00-overview.md)
- Azərbaycanca: [az/00-overview.md](az/00-overview.md)
- Türkçe: [tr/00-overview.md](tr/00-overview.md)
- Русский: [ru/00-overview.md](ru/00-overview.md)

The panel itself is in Azerbaijani and English, so the Turkish and Russian guides use the English panel screenshots.

## PDF

`build-pdf.mjs` makes one PDF per language, with a table of contents and page numbers:

```sh
npm i --no-save markdown-it playwright && npx playwright install chromium
node docs/guide/build-pdf.mjs                 # docs/guide/dist/Clomni-Mobile-SDK-Guide-{en,az,tr,ru}.pdf
node docs/guide/build-pdf.mjs --lang az --out /tmp/guide
```

The TOC's page numbers need `pdftotext` (poppler-utils). The PDFs are not kept in the repository.

The guide is also in the Clomni panel: the inbox page → side menu → **Guide**. Both PDFs download from there
(`public/docs/mobile-sdk/` in the Clomni repository).

Where the screenshots come from, and how to add real ones for Firebase, Apple, Xcode, Android Studio and Unity
(the guide gives a text path there): [SCREENSHOTS.md](SCREENSHOTS.md).
