#if UNITY_IOS
using System.Collections.Generic;
using System.Runtime.InteropServices;
using UnityEngine;

namespace ClomniMessenger
{
    /// <summary>
    /// iOS: the C functions of Plugins/iOS/ClomniUnityBridge.swift, which call the ClomniMessenger pod. Dictionaries
    /// travel as JSON text, flags as 0/1; events come back through UnitySendMessage to ClomniReceiver.
    /// </summary>
    internal sealed class ClomniIOS : IClomniNative
    {
        public void Initialize(string appId, string apiKey, string region)
        {
            clomni_unity_install(ClomniReceiver.ObjectName);
            clomni_initialize(appId, apiKey, region);
        }

        public void LoginUser(ClomniUser user, string userHash) =>
            clomni_login_user(user.UserId, user.Email, user.Phone, user.Name, userHash);

        public void LoginUnidentifiedUser() => clomni_login_unidentified_user();

        public void UpdateUser(string name, string language, IDictionary<string, object> customAttributes) =>
            clomni_update_user(name, language, customAttributes == null ? null : ClomniJson.Write(customAttributes));

        public void Logout() => clomni_logout();

        public void SetLogLevel(ClomniLogLevel level) => clomni_set_log_level(level.ToString().ToLowerInvariant());

        public void SetTypeface(string familyName) => clomni_set_typeface(familyName);

        public void SetTheme(string primaryColor, string typeface, ClomniThemeMode? mode) =>
            clomni_set_theme(primaryColor, typeface, mode?.ToString().ToLowerInvariant());

        public void SetSoundsEnabled(bool enabled) => clomni_set_sounds_enabled(enabled ? 1 : 0);

        public void SetLanguage(string language) => clomni_set_language(language);

        public void SetLinkListener(bool enabled) => clomni_set_link_listener(enabled ? 1 : 0);

        public void Present(string source) => clomni_present(source);

        public void PresentNewConversation(string source) => clomni_present_new_conversation(source);

        public void PresentConversation(string conversationId) => clomni_present_conversation(conversationId);

        public void Dismiss() => clomni_dismiss();

        public void StartFlow(string eventName, IDictionary<string, object> data, bool openMessenger, string source) =>
            clomni_start_flow(eventName, ClomniJson.Write(data), openMessenger ? 1 : 0, source);

        public void SetLauncherVisible(bool visible) => clomni_set_launcher_visible(visible ? 1 : 0);

        public void SetBottomPadding(float padding) => clomni_set_bottom_padding(padding);

        public void SetDeviceToken(string token) => clomni_set_device_token(token);

        public void HandlePush(IDictionary<string, string> data) => clomni_handle_push(ClomniJson.Write(data));

        public bool ShouldShowForeground(IDictionary<string, string> data) =>
            clomni_should_show_foreground(ClomniJson.Write(data)) != 0;

        public void SetNotificationIcon(string drawableName) =>
            Debug.LogWarning("[Clomni] SetNotificationIcon is Android only");

        [DllImport("__Internal")] private static extern void clomni_unity_install(string receiver);
        [DllImport("__Internal")] private static extern void clomni_initialize(string appId, string apiKey, string region);
        [DllImport("__Internal")] private static extern void clomni_login_user(string userId, string email, string phone, string name, string userHash);
        [DllImport("__Internal")] private static extern void clomni_login_unidentified_user();
        [DllImport("__Internal")] private static extern void clomni_update_user(string name, string language, string customAttributesJson);
        [DllImport("__Internal")] private static extern void clomni_logout();
        [DllImport("__Internal")] private static extern void clomni_set_log_level(string level);
        [DllImport("__Internal")] private static extern void clomni_set_typeface(string familyName);
        [DllImport("__Internal")] private static extern void clomni_set_theme(string primaryColor, string typeface, string mode);
        [DllImport("__Internal")] private static extern void clomni_set_sounds_enabled(int enabled);
        [DllImport("__Internal")] private static extern void clomni_set_language(string language);
        [DllImport("__Internal")] private static extern void clomni_set_link_listener(int enabled);
        [DllImport("__Internal")] private static extern void clomni_present(string source);
        [DllImport("__Internal")] private static extern void clomni_present_new_conversation(string source);
        [DllImport("__Internal")] private static extern void clomni_present_conversation(string conversationId);
        [DllImport("__Internal")] private static extern void clomni_dismiss();
        [DllImport("__Internal")] private static extern void clomni_start_flow(string eventName, string dataJson, int openMessenger, string source);
        [DllImport("__Internal")] private static extern void clomni_set_launcher_visible(int visible);
        [DllImport("__Internal")] private static extern void clomni_set_bottom_padding(double padding);
        [DllImport("__Internal")] private static extern void clomni_set_device_token(string hexToken);
        [DllImport("__Internal")] private static extern void clomni_handle_push(string dataJson);
        [DllImport("__Internal")] private static extern int clomni_should_show_foreground(string dataJson);
    }
}
#endif
