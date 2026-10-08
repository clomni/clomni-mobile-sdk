# Clomni Mobile SDK guide

The integration guide for app developers, step by step and with screenshots.

- English: [en/00-overview.md](en/00-overview.md)
- Azərbaycanca: [az/00-overview.md](az/00-overview.md)

## PDF

`build-pdf.mjs` makes one PDF per language, with a table of contents and page numbers:

```sh
npm i --no-save markdown-it playwright && npx playwright install chromium
node docs/guide/build-pdf.mjs                 # docs/guide/dist/Clomni-Mobile-SDK-Guide-{en,az}.pdf
node docs/guide/build-pdf.mjs --lang az --out /tmp/guide
```

The TOC's page numbers need `pdftotext` (poppler-utils). The PDFs are not kept in the repository.

Where the screenshots come from, and how to add real ones for Firebase, Apple, Xcode, Android Studio and Unity
(the guide gives a text path there): [SCREENSHOTS.md](SCREENSHOTS.md).
