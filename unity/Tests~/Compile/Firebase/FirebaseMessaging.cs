// Signatures only: the parts of the Firebase Unity SDK the Push sample uses.
using System;
using System.Collections.Generic;

namespace Firebase.Messaging
{
    public static class FirebaseMessaging
    {
        public static event EventHandler<TokenReceivedEventArgs> TokenReceived;
        public static event EventHandler<MessageReceivedEventArgs> MessageReceived;
    }

    public sealed class TokenReceivedEventArgs : EventArgs
    {
        public string Token => throw null;
    }

    public sealed class MessageReceivedEventArgs : EventArgs
    {
        public FirebaseMessage Message => throw null;
    }

    public sealed class FirebaseMessage
    {
        public IDictionary<string, string> Data => throw null;
        public bool NotificationOpened => throw null;
    }
}
