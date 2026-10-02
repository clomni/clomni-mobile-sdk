package ai.clomni.messenger.presentation

/**
 * Apar's config in the v2 shape of APPEARANCE-CONTRACT 1 (the contract's example with fixture 42's values), until
 * the server's fixtures arrive through scripts/sync-protocol.sh.
 */
internal const val APAR_CONFIG_V2 = """{
  "version": 12,
  "brand": {
    "name": "Apar",
    "logo_url": "https://app.clomni.ai/a/apar.png",
    "logo_dark_url": null,
    "primary_color": "#1F9D63",
    "header_style": "gradient",
    "header_image_url": null,
    "glow": false,
    "colors": {
      "light": { "primary": "#1F9D63", "on_primary": "#000000", "primary_soft": "#E9F5EF", "primary_line": "#CEE9DD",
                 "header_from": "#1F9D63", "header_to": "#177248", "header_text": "#FFFFFF" },
      "dark":  { "primary": "#27C87E", "on_primary": "#000000", "primary_soft": "#142520", "primary_line": "#173B2D",
                 "header_from": "#1F9D63", "header_to": "#0E482D", "header_text": "#FFFFFF" }
    }
  },
  "team": {
    "show": true,
    "mode": "auto",
    "avatars": ["https://app.clomni.ai/a/leyla.png", "https://app.clomni.ai/a/rauf.png", "https://app.clomni.ai/a/nigar.png"],
    "reply_time": "Adətən bir neçə dəqiqəyə cavab veririk",
    "reply_time_offline": "Hazırda iş saatı deyil, sizə səhər cavab verəcəyik",
    "office_hours": { "tz": "Asia/Baku", "open_now": true, "next_open_at": null }
  },
  "bot": { "name": "Clomni", "avatar_url": "https://app.clomni.ai/a/bot.png" },
  "home": {
    "cards": ["send", "recent", "channels"],
    "channels": [
      { "type": "instagram", "url": "https://instagram.com/apar.az" },
      { "type": "whatsapp", "url": "https://wa.me/994501234567" },
      { "type": "linkedin", "url": "https://linkedin.com/company/apar" },
      { "type": "email", "url": "mailto:support@apar.az" }
    ]
  },
  "theme": { "mode": "system", "launcher": { "enabled": false, "position": "right", "bottom_padding": 20 } },
  "composer": { "attachments": true, "emoji": true },
  "languages": ["az", "en", "ru"],
  "strings": {
    "greeting_line1": "Salam, {first_name} 👋",
    "greeting_line1_anonymous": "Salam 👋",
    "greeting_line2": "Necə kömək edə bilərik?",
    "send_card_title": "Bizə mesaj göndərin",
    "composer_placeholder": "Mesaj yazın…",
    "today": "Bu gün",
    "sent": "Göndərildi",
    "read": "Oxundu"
  },
  "limits": { "image_mb": 10, "file_mb": 25, "text_chars": 4000 },
  "powered_by": true
}"""
