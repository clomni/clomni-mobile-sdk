using System.Collections.Generic;
using ClomniMessenger;
using UnityEngine;

/// <summary>
/// Three buttons over any scene: open the messenger, log a user in, start a flow. Put it on an empty GameObject and
/// fill in the App ID and the API key of the platform you build for (Clomni → Channels → Mobile app).
/// </summary>
public sealed class ClomniBasicSample : MonoBehaviour
{
    [SerializeField] private string appId = "app_...";
    [SerializeField] private string androidApiKey = "android_...";
    [SerializeField] private string iosApiKey = "ios_...";

    private int unread;

    private void Start()
    {
        var apiKey = Application.platform == RuntimePlatform.IPhonePlayer ? iosApiKey : androidApiKey;
        Clomni.Initialize(appId, apiKey);
        Clomni.UnreadCountChanged += OnUnreadCountChanged;
        // Without this the system opens a news item's link; with it the game decides.
        Clomni.OnLink += Application.OpenURL;
    }

    private void OnDestroy()
    {
        Clomni.UnreadCountChanged -= OnUnreadCountChanged;
        Clomni.OnLink -= Application.OpenURL;
    }

    private void OnUnreadCountChanged(int count) => unread = count;

    private void OnGUI()
    {
        GUI.skin.button.fontSize = 36;
        GUILayout.BeginArea(new Rect(40, 120, Screen.width - 80, Screen.height - 240));
        var height = GUILayout.Height(120);

        if (GUILayout.Button(unread > 0 ? $"Aç ({unread})" : "Aç", height))
        {
            Clomni.Present("sample_button");
        }

        if (GUILayout.Button("Login", height))
        {
            // userHash is hex(HMAC-SHA256(identity_secret, userId)), made by the game's own server. Never put
            // identity_secret into the game. Without a hash, an inbox that requires it refuses the login.
            Clomni.LoginUser(new ClomniUser { UserId = "demo-42", Email = "demo@example.com", Name = "Demo" }, userHash: null);
        }

        if (GUILayout.Button("Hadisə göndər", height))
        {
            Clomni.StartFlow("ride_problem", new Dictionary<string, object> { ["ride_id"] = "R-1001" }, openMessenger: true,
                source: "sample_button");
        }

        GUILayout.EndArea();
    }
}
