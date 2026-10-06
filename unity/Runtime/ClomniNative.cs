using System.Collections.Concurrent;
using System.Collections.Generic;
using UnityEngine;

namespace ClomniMessenger
{
    /// <summary>One platform's native SDK. Arguments are already checked by <see cref="Clomni"/>.</summary>
    internal interface IClomniNative
    {
        void Initialize(string appId, string apiKey, string region);
        void LoginUser(ClomniUser user, string userHash);
        void LoginUnidentifiedUser();
        void UpdateUser(string name, string language, IDictionary<string, object> customAttributes);
        void Logout();
        void SetLogLevel(ClomniLogLevel level);
        void SetTypeface(string familyName);
        void SetTheme(string primaryColor, string typeface, ClomniThemeMode? mode);
        void SetSoundsEnabled(bool enabled);
        void SetLanguage(string language);
        void SetLinkListener(bool enabled);
        void Present(string source);
        void PresentNewConversation(string source);
        void PresentConversation(string conversationId);
        void Dismiss();
        void StartFlow(string eventName, IDictionary<string, object> data, bool openMessenger, string source);
        void SetLauncherVisible(bool visible);
        void SetBottomPadding(float padding);
        void SetDeviceToken(string token);
        void HandlePush(IDictionary<string, string> data);
        bool ShouldShowForeground(IDictionary<string, string> data);
        void SetNotificationIcon(string drawableName);
    }

    /// <summary>
    /// Brings the native SDKs' events to Unity's main thread as "name" or "name\ntext". iOS sends them with
    /// UnitySendMessage to this object; Android's listeners run on Android's main thread and queue them for the next
    /// frame.
    /// </summary>
    internal sealed class ClomniReceiver : MonoBehaviour
    {
        internal const string ObjectName = "ClomniMessenger";

        private static readonly ConcurrentQueue<string> Pending = new ConcurrentQueue<string>();
        private static ClomniReceiver instance;

        internal static void Ensure()
        {
            if (instance != null) return;
            var holder = new GameObject(ObjectName);
            DontDestroyOnLoad(holder);
            instance = holder.AddComponent<ClomniReceiver>();
        }

        internal static void Post(string message) => Pending.Enqueue(message);

        private void Update()
        {
            while (Pending.TryDequeue(out var message)) Clomni.Dispatch(message);
        }

        // Called by UnitySendMessage from ClomniUnityBridge.swift.
        private void OnClomniEvent(string message) => Clomni.Dispatch(message);
    }
}
