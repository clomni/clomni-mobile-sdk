# Şəkillər

## Firebase, Apple Developer, Xcode, Android Studio və Unity

Bu ekranlar üçün təlimatda şəkil yoxdur. Onların yerində "Yol" qutusu durur: düymələrin konsoldakı ingiliscə adı ilə
naviqasiya yolu, lazımi seçim və rəsmi sənədin linki. Konsolların şəkillərini internetdən götürmürük (müəllif hüququ).

İstəyə bağlı: sonra öz hesabımızda çəkilmiş real şəkil əlavə etmək olar.

- Şəkli `docs/guide/images/` qovluğuna qoyun və Markdown-da "Yol" qutusunun altına `![...](../images/<ad>.png)` yazın.
  Şəkil qutunu əvəz etmir, onun altına əlavə olunur.
- PNG, eni 1400 px-dən çox olmasın. Lazımi yeri qırmızı çərçivə ilə göstərin, panel şəkillərindəki kimi.
- Açar, ID, e-poçt, layihə adı və şirkət adı görünürsə, bulanıqlaşdırın. Nümunə ad lazımdırsa, `Example` və
  `com.example.app` işlədin.
- Sonra PDF-i yenidən yaradın: `node docs/guide/build-pdf.mjs`.

## SDK ekranları

`sdk-screens.png`, `sdk-theme.png` və `sdk-launcher.png` Android SDK-nın Paparazzi şəkillərindən yığılıb
(`android/messenger/src/test/snapshots/images`). Repozitoriyada iOS ekran şəkilləri yoxdur. iOS SDK eyni ekranları
çəkdiyi üçün təlimat Android şəkillərini işlədir və bunu ilk bölmədə deyir. iOS şəkilləri çəkiləndə onları ayrıca
əlavə etmək olar.

## Panel şəkilləri

`panel-*-az.png` və `panel-*-en.png` dev.clomni.co-da (hesab 7, "Clomni Demo tətbiq" kanalı) Playwright ilə
çəkilib. Açarlar, Key ID, Team ID, e-poçtlar və Firebase layihəsinin adı bulanıqlaşdırılıb. Panel dəyişəndə onları
yenidən çəkmək lazım ola bilər.

- Kanal səhifəsinin hər şəklində soldakı menyu də var. Açıq bölmə nömrəsiz qırmızı çərçivədədir, səhifədəki
  addımlar nömrəli çərçivələrdədir.
- Səhifənin aşağısındakı hissələr (test push, dillər, tema və s.) səhifə həmin yerə sürüşdürülüb çəkilir. Menyu
  yerində qalır, ona görə bu şəkillərdə də görünür.
