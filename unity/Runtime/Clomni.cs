using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using UnityEngine;

namespace ClomniMessenger
{
    /// <summary>
    /// The Clomni Messenger (brief 8 · 9): the same calls as the native SDKs, which do the work. On Android and iOS
    /// devices; in the Editor and on other platforms every call does nothing and the first one says so in the log.
    /// Call from Unity's main thread. Events arrive on the main thread.
    /// </summary>
    public static class Clomni
    {
        private static readonly Regex HexColor = new Regex("^#[0-9A-Fa-f]{6}$");

        private static IClomniNative native;
        private static bool resolved;
        private static Action<string> link;

        /// <summary>The unread count, on every change.</summary>
        public static event Action<int> UnreadCountChanged;

        /// <summary>With the <c>source</c> given to <see cref="Present"/>, or null.</summary>
        public static event Action<string> MessengerOpened;

        public static event Action MessengerClosed;

        /// <summary>With the new conversation's id.</summary>
        public static event Action<string> ConversationStarted;

        /// <summary>A flow reached its end, with the flow's id.</summary>
        public static event Action<string> FlowCompleted;

        /// <summary>
        /// A link the messenger is about to open (a news item's button: a web address or the app's own deep link).
        /// While anything listens, the link comes here and the app opens it its own way; with no listener the system
        /// opens it.
        /// </summary>
        public static event Action<string> OnLink
        {
            add
            {
                var first = link == null;
                link += value;
                if (first && link != null) Native?.SetLinkListener(true);
            }
            remove
            {
                if (link == null) return;
                link -= value;
                if (link == null) Native?.SetLinkListener(false);
            }
        }

        /// <summary>Prepares the connection and push; adds nothing to the app's screens. Call it once, at the app's
        /// start, with the App ID and the platform's API key from Clomni (Channels → Mobile app).</summary>
        public static void Initialize(string appId, string apiKey, string region = "eu")
        {
            if (string.IsNullOrEmpty(appId) || string.IsNullOrEmpty(apiKey))
            {
                Debug.LogError("[Clomni] Initialize: appId and apiKey are required");
                return;
            }
            Native?.Initialize(appId, apiKey, string.IsNullOrEmpty(region) ? "eu" : region);
        }

        /// <summary>
        /// The app's logged-in user. <paramref name="userHash"/> is hex(HMAC-SHA256(identity_secret, UserId)),
        /// computed on the app's server; identity_secret never goes into the app.
        /// </summary>
        public static void LoginUser(ClomniUser user, string userHash = null)
        {
            if (user == null)
            {
                Debug.LogError("[Clomni] LoginUser: user is null");
                return;
            }
            Native?.LoginUser(user, userHash);
        }

        /// <summary>An anonymous visitor, the same one on this device until <see cref="Logout"/>.</summary>
        public static void LoginUnidentifiedUser() => Native?.LoginUnidentifiedUser();

        /// <summary>Only what is given changes; <paramref name="customAttributes"/> are merged with the user's.
        /// <paramref name="language"/> is "az", "en" or "ru".</summary>
        public static void UpdateUser(string name = null, string language = null,
            IDictionary<string, object> customAttributes = null)
        {
            if (customAttributes != null && !ClomniJson.IsJson(customAttributes))
            {
                Debug.LogError("[Clomni] UpdateUser: customAttributes hold something JSON cannot carry");
                return;
            }
            if (name == null && language == null && customAttributes == null)
            {
                Debug.LogWarning("[Clomni] UpdateUser: nothing to change");
                return;
            }
            Native?.UpdateUser(name, language, customAttributes);
        }

        /// <summary>Ends the session and deletes the messenger's data on this device; call it when the app's user
        /// logs out.</summary>
        public static void Logout() => Native?.Logout();

        public static void SetLogLevel(ClomniLogLevel level) => Native?.SetLogLevel(level);

        /// <summary>The app's own font family for the messenger's texts; null is the system font.</summary>
        public static void SetTypeface(string familyName) => Native?.SetTypeface(familyName);

        /// <summary>
        /// The app's own look over the panel's: its colour ("#RRGGBB"), font and mode. Each call replaces the last;
        /// what is left out stays the panel's.
        /// </summary>
        public static void SetTheme(string primaryColor = null, string typeface = null, ClomniThemeMode? mode = null)
        {
            if (primaryColor != null && !HexColor.IsMatch(primaryColor))
            {
                Debug.LogError($"[Clomni] SetTheme: primaryColor \"{primaryColor}\" is not #RRGGBB; the panel's colour stays");
                primaryColor = null;
            }
            Native?.SetTheme(primaryColor, typeface, mode);
        }

        /// <summary>The short sounds for a message received while the conversation is open and one sent. On unless
        /// the panel turns them off; false turns them off whatever the panel says.</summary>
        public static void SetSoundsEnabled(bool enabled) => Native?.SetSoundsEnabled(enabled);

        /// <summary>"az", "en" or "ru", used when the panel has it on; null (the default) follows the phone.</summary>
        public static void SetLanguage(string language) => Native?.SetLanguage(language);

        /// <summary>Home. <paramref name="source"/> says where in the app (for example "profile_support").</summary>
        public static void Present(string source = null) => Native?.Present(source);

        /// <summary>Straight into a new conversation, with the inbox's first flow.</summary>
        public static void PresentNewConversation(string source = null) => Native?.PresentNewConversation(source);

        public static void PresentConversation(string conversationId)
        {
            if (string.IsNullOrEmpty(conversationId))
            {
                Debug.LogError("[Clomni] PresentConversation: conversationId is required");
                return;
            }
            Native?.PresentConversation(conversationId);
        }

        public static void Dismiss() => Native?.Dismiss();

        /// <summary>
        /// Starts the flow bound to an app event (for example "ride_problem") in a new conversation; its texts can use
        /// <paramref name="data"/> as <c>{{data.ride_id}}</c>. Nothing happens when no flow is bound to the event.
        /// With <paramref name="openMessenger"/> the conversation opens on screen; otherwise the user learns of it
        /// from a push or the unread count.
        /// </summary>
        public static void StartFlow(string eventName, IDictionary<string, object> data = null,
            bool openMessenger = false, string source = null)
        {
            if (string.IsNullOrEmpty(eventName))
            {
                Debug.LogError("[Clomni] StartFlow: eventName is required");
                return;
            }
            if (data != null && !ClomniJson.IsJson(data))
            {
                Debug.LogError("[Clomni] StartFlow: data holds something JSON cannot carry");
                return;
            }
            Native?.StartFlow(eventName, data ?? new Dictionary<string, object>(), openMessenger, source);
        }

        /// <summary>The floating button: off by default, and the panel can turn it on too. The app's choice wins.
        /// </summary>
        public static void SetLauncherVisible(bool visible) => Native?.SetLauncherVisible(visible);

        /// <summary>Lifts the launcher above the app's own bottom bar (points on iOS, dp on Android).</summary>
        public static void SetBottomPadding(float padding) => Native?.SetBottomPadding(padding);

        /// <summary>The push token: the APNs device token as hex on iOS, the FCM token on Android.</summary>
        public static void SetDeviceToken(string token)
        {
            if (string.IsNullOrEmpty(token))
            {
                Debug.LogError("[Clomni] SetDeviceToken: token is empty");
                return;
            }
            Native?.SetDeviceToken(token);
        }

        /// <summary>Whether a push is Clomni's; the app's own pushes are the app's to handle.</summary>
        public static bool IsClomniPush(IDictionary<string, string> data) =>
            data != null && data.TryGetValue("clomni", out var flag) && flag == "1";

        /// <summary>
        /// A Clomni push, as each platform delivers it. Android: the FCM data message as it arrives; the SDK shows it
        /// as a notification whose tap opens the conversation. iOS: the tap on its notification, which opens the
        /// conversation. False for the app's own pushes, which stay the app's.
        /// </summary>
        public static bool HandlePush(IDictionary<string, string> data)
        {
            if (!IsClomniPush(data)) return false;
            Native?.HandlePush(data);
            return true;
        }

        /// <summary>iOS: for a push that arrives while the app is open, false for a Clomni push while the messenger
        /// is open (it shows the message itself). Android shows or hides its notifications itself: always true there.
        /// </summary>
        public static bool ShouldShowForeground(IDictionary<string, string> data)
        {
            if (!IsClomniPush(data)) return true;
            return Native?.ShouldShowForeground(data) ?? true;
        }

        /// <summary>Android: the small icon of Clomni's notifications, a drawable's name. Nothing on iOS.</summary>
        public static void SetNotificationIcon(string drawableName) => Native?.SetNotificationIcon(drawableName);

        /// <summary>The platform's SDK; null, after one log line, in the Editor and on other platforms.</summary>
        private static IClomniNative Native
        {
            get
            {
                if (!resolved)
                {
                    resolved = true;
                    native = Create();
                    if (native == null)
                    {
                        Debug.Log($"[Clomni] The messenger runs on Android and iOS devices; on {Application.platform} its calls do nothing.");
                    }
                }
                if (native != null) ClomniReceiver.Ensure();
                return native;
            }
        }

        private static IClomniNative Create()
        {
#if UNITY_ANDROID && !UNITY_EDITOR
            return new ClomniAndroid();
#elif UNITY_IOS && !UNITY_EDITOR
            return new ClomniIOS();
#else
            return null;
#endif
        }

        /// <summary>A native event, "name" or "name\ntext", on the main thread.</summary>
        internal static void Dispatch(string message)
        {
            var split = message.IndexOf('\n');
            var name = split < 0 ? message : message.Substring(0, split);
            var text = split < 0 ? null : message.Substring(split + 1);
            switch (name)
            {
                case "link":
                    link?.Invoke(text ?? "");
                    break;
                case "unreadCountChanged":
                    UnreadCountChanged?.Invoke(int.TryParse(text, out var count) ? count : 0);
                    break;
                case "messengerOpened":
                    MessengerOpened?.Invoke(text);
                    break;
                case "messengerClosed":
                    MessengerClosed?.Invoke();
                    break;
                case "conversationStarted":
                    ConversationStarted?.Invoke(text ?? "");
                    break;
                case "flowCompleted":
                    FlowCompleted?.Invoke(text ?? "");
                    break;
            }
        }
    }
}
