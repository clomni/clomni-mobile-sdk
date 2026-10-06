using ClomniMessenger;
using Firebase.Messaging;
using UnityEngine;

/// <summary>
/// Hands Firebase Cloud Messaging's token and messages to Clomni. Needs the Firebase Unity SDK
/// (FirebaseMessaging.unitypackage) and the app's google-services.json / GoogleService-Info.plist. Put it on a
/// GameObject that lives as long as the game, next to the one that calls Clomni.Initialize.
/// </summary>
public sealed class ClomniFirebaseBridge : MonoBehaviour
{
    private void Start()
    {
        FirebaseMessaging.TokenReceived += OnTokenReceived;
        FirebaseMessaging.MessageReceived += OnMessageReceived;
    }

    private void OnDestroy()
    {
        FirebaseMessaging.TokenReceived -= OnTokenReceived;
        FirebaseMessaging.MessageReceived -= OnMessageReceived;
    }

    private void OnTokenReceived(object sender, TokenReceivedEventArgs e)
    {
        // Android takes the FCM token. iOS takes the APNs device token instead (README → Push → iOS).
        if (Application.platform == RuntimePlatform.Android) Clomni.SetDeviceToken(e.Token);
    }

    private void OnMessageReceived(object sender, MessageReceivedEventArgs e)
    {
        var message = e.Message;
        // Android: every data message as it arrives; the SDK shows Clomni's as a notification.
        // iOS: only the tap on a notification, which opens the conversation.
        if (Application.platform == RuntimePlatform.IPhonePlayer && !message.NotificationOpened) return;
        if (Clomni.HandlePush(message.Data)) return;
        // The game's own push.
    }
}
