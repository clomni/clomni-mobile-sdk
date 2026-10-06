#if UNITY_ANDROID
using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace ClomniMessenger
{
    /// <summary>
    /// Android: <c>ai.clomni.messenger.Clomni</c> and <c>ClomniPush</c> (Kotlin objects with static methods). Every
    /// call names its JVM signature as android/messenger/api/messenger.api lists it, so a null argument still finds
    /// its overload; Tests~/check-android-api.py compares the two.
    /// </summary>
    internal sealed class ClomniAndroid : IClomniNative
    {
        private const string Package = "ai/clomni/messenger/";

        private readonly AndroidJavaClass clomni = new AndroidJavaClass("ai.clomni.messenger.Clomni");
        private readonly AndroidJavaClass push = new AndroidJavaClass("ai.clomni.messenger.ClomniPush");
        private readonly AndroidJavaObject context;

        // The SDK keeps the listeners; these keep the C# side of each alive.
        private readonly List<AndroidJavaProxy> listeners = new List<AndroidJavaProxy>();
        private LinkProxy linkProxy;

        internal ClomniAndroid()
        {
            using (var player = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
            using (var activity = player.GetStatic<AndroidJavaObject>("currentActivity"))
            {
                context = activity.Call<AndroidJavaObject>("getApplicationContext");
            }
        }

        public void Initialize(string appId, string apiKey, string region)
        {
            Static(clomni, "initialize", "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
                context, appId, apiKey, region);
            listeners.Clear();
            Listen("onUnreadCountChanged", "UnreadCountListener", new UnreadProxy());
            Listen("onMessengerOpened", "MessengerOpenedListener", new OpenedProxy());
            Listen("onMessengerClosed", "MessengerClosedListener", new ClosedProxy());
            Listen("onConversationStarted", "ConversationStartedListener", new TextProxy("ConversationStartedListener", "conversationStarted"));
            Listen("onFlowCompleted", "FlowCompletedListener", new TextProxy("FlowCompletedListener", "flowCompleted"));
        }

        public void LoginUser(ClomniUser user, string userHash)
        {
            using (var refs = new Refs())
            {
                var javaUser = refs.New(Package + "ClomniUser",
                    "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V",
                    user.UserId, user.Email, user.Phone, user.Name);
                Static(clomni, "loginUser", "(Lai/clomni/messenger/ClomniUser;Ljava/lang/String;)V", new JavaRef(javaUser), userHash);
            }
        }

        public void LoginUnidentifiedUser() => Static(clomni, "loginUnidentifiedUser", "()V");

        public void UpdateUser(string name, string language, IDictionary<string, object> customAttributes) =>
            Static(clomni, "updateUser", "(Ljava/lang/String;Ljava/lang/String;Ljava/util/Map;)V", name, language, customAttributes);

        public void Logout() => Static(clomni, "logout", "()V");

        public void SetLogLevel(ClomniLogLevel level)
        {
            using (var refs = new Refs())
            {
                var value = refs.Enum("ClomniLogLevel", level.ToString().ToUpperInvariant());
                Static(clomni, "setLogLevel", "(Lai/clomni/messenger/ClomniLogLevel;)V", new JavaRef(value));
            }
        }

        public void SetTypeface(string familyName)
        {
            using (var refs = new Refs())
            {
                Static(clomni, "setTypeface", "(Landroid/graphics/Typeface;)V", new JavaRef(refs.Typeface(familyName)));
            }
        }

        public void SetTheme(string primaryColor, string typeface, ClomniThemeMode? mode)
        {
            using (var refs = new Refs())
            {
                var themeMode = mode.HasValue ? refs.Enum("ClomniThemeMode", mode.Value.ToString().ToUpperInvariant()) : IntPtr.Zero;
                Static(clomni, "setTheme",
                    "(Ljava/lang/String;Landroid/graphics/Typeface;Lai/clomni/messenger/ClomniThemeMode;)V",
                    primaryColor, new JavaRef(refs.Typeface(typeface)), new JavaRef(themeMode));
            }
        }

        public void SetSoundsEnabled(bool enabled) => Static(clomni, "setSoundsEnabled", "(Z)V", enabled);

        public void SetLanguage(string language) => Static(clomni, "setLanguage", "(Ljava/lang/String;)V", language);

        public void SetLinkListener(bool enabled)
        {
            linkProxy = enabled ? new LinkProxy() : null;
            Static(clomni, "onLink", "(Lai/clomni/messenger/LinkListener;)V", linkProxy);
        }

        public void Present(string source) => Static(clomni, "present", "(Ljava/lang/String;)V", source);

        public void PresentNewConversation(string source) =>
            Static(clomni, "presentNewConversation", "(Ljava/lang/String;)V", source);

        public void PresentConversation(string conversationId) =>
            Static(clomni, "presentConversation", "(Ljava/lang/String;)V", conversationId);

        public void Dismiss() => Static(clomni, "dismiss", "()V");

        public void StartFlow(string eventName, IDictionary<string, object> data, bool openMessenger, string source) =>
            Static(clomni, "startFlow", "(Ljava/lang/String;Ljava/util/Map;ZLjava/lang/String;)V",
                eventName, data, openMessenger, source);

        public void SetLauncherVisible(bool visible) => Static(clomni, "setLauncherVisible", "(Z)V", visible);

        public void SetBottomPadding(float padding) =>
            Static(clomni, "setBottomPadding", "(I)V", (int)Math.Round(padding));

        public void SetDeviceToken(string token) => Static(clomni, "setDeviceToken", "(Ljava/lang/String;)V", token);

        public void HandlePush(IDictionary<string, string> data)
        {
            var values = new Dictionary<string, object>();
            foreach (var entry in data) values[entry.Key] = entry.Value;
            Static(push, "handle", "(Landroid/content/Context;Ljava/util/Map;)Z", context, values);
        }

        public bool ShouldShowForeground(IDictionary<string, string> data) => true;

        public void SetNotificationIcon(string drawableName)
        {
            int id;
            using (var resources = context.Call<AndroidJavaObject>("getResources"))
            {
                id = resources.Call<int>("getIdentifier", drawableName ?? "", "drawable", context.Call<string>("getPackageName"));
            }
            if (id == 0)
            {
                Debug.LogError($"[Clomni] SetNotificationIcon: no drawable \"{drawableName}\" in the app");
                return;
            }
            Static(clomni, "setNotificationIcon", "(I)V", id);
        }

        private void Listen(string setter, string listenerInterface, AndroidJavaProxy proxy)
        {
            listeners.Add(proxy);
            Static(clomni, setter, "(L" + Package + listenerInterface + ";)V", proxy);
        }

        /// <summary>A static method by its exact JVM signature; a Java exception is logged, not thrown.</summary>
        private static void Static(AndroidJavaClass owner, string name, string signature, params object[] args)
        {
            var type = owner.GetRawClass();
            var method = AndroidJNI.GetStaticMethodID(type, name, signature);
            if (method == IntPtr.Zero)
            {
                AndroidJNI.ExceptionClear();
                Debug.LogError($"[Clomni] {name}{signature} is not in this SDK build");
                return;
            }
            using (var refs = new Refs())
            {
                var values = refs.Args(args);
                if (signature.EndsWith(")Z", StringComparison.Ordinal)) AndroidJNI.CallStaticBooleanMethod(type, method, values);
                else AndroidJNI.CallStaticVoidMethod(type, method, values);
            }
            Failed(name);
        }

        private static bool Failed(string name)
        {
            var error = AndroidJNI.ExceptionOccurred();
            if (error == IntPtr.Zero) return false;
            AndroidJNI.ExceptionDescribe();
            AndroidJNI.ExceptionClear();
            AndroidJNI.DeleteLocalRef(error);
            Debug.LogError($"[Clomni] {name} threw on the Java side; see logcat");
            return true;
        }

        /// <summary>A Java reference the caller owns, passed as is.</summary>
        private readonly struct JavaRef
        {
            internal readonly IntPtr Value;
            internal JavaRef(IntPtr value) => Value = value;
        }

        /// <summary>Java values made from C# ones; the local references are deleted with this.</summary>
        private sealed class Refs : IDisposable
        {
            private readonly List<IntPtr> owned = new List<IntPtr>();

            internal jvalue[] Args(object[] args)
            {
                var values = new jvalue[args.Length];
                for (var i = 0; i < args.Length; i++)
                {
                    switch (args[i])
                    {
                        case bool flag:
                            values[i].z = flag;
                            break;
                        case int number:
                            values[i].i = number;
                            break;
                        case JavaRef reference:
                            values[i].l = reference.Value;
                            break;
                        case AndroidJavaObject javaObject:
                            values[i].l = javaObject.GetRawObject();
                            break;
                        case AndroidJavaProxy proxy:
                            values[i].l = Own(AndroidJNIHelper.CreateJavaProxy(proxy));
                            break;
                        default:
                            values[i].l = Java(args[i]);
                            break;
                    }
                }
                return values;
            }

            /// <summary>A Java value for a JSON-like C# one (see ClomniJson.IsJson).</summary>
            internal IntPtr Java(object value)
            {
                switch (value)
                {
                    case null:
                        return IntPtr.Zero;
                    case string text:
                        return Own(AndroidJNI.NewString(text));
                    case bool flag:
                        return Box("java/lang/Boolean", "(Z)Ljava/lang/Boolean;", new jvalue { z = flag });
                    case float _:
                    case double _:
                    case decimal _:
                        return Box("java/lang/Double", "(D)Ljava/lang/Double;", new jvalue { d = Convert.ToDouble(value) });
                    case IDictionary map:
                        var hashMap = New("java/util/HashMap", "()V");
                        var put = Method("java/util/HashMap", "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
                        foreach (DictionaryEntry entry in map)
                        {
                            var previous = AndroidJNI.CallObjectMethod(hashMap, put,
                                new[] { new jvalue { l = Java(entry.Key) }, new jvalue { l = Java(entry.Value) } });
                            if (previous != IntPtr.Zero) AndroidJNI.DeleteLocalRef(previous);
                        }
                        return hashMap;
                    case IEnumerable list:
                        var arrayList = New("java/util/ArrayList", "()V");
                        var add = Method("java/util/ArrayList", "add", "(Ljava/lang/Object;)Z");
                        foreach (var item in list) AndroidJNI.CallBooleanMethod(arrayList, add, new[] { new jvalue { l = Java(item) } });
                        return arrayList;
                    default:
                        return ClomniJson.IsInteger(value)
                            ? Box("java/lang/Long", "(J)Ljava/lang/Long;", new jvalue { j = Convert.ToInt64(value) })
                            : Own(AndroidJNI.NewString(Convert.ToString(value)));
                }
            }

            internal IntPtr New(string className, string signature, params object[] args)
            {
                var type = Own(AndroidJNI.FindClass(className));
                return Own(AndroidJNI.NewObject(type, AndroidJNI.GetMethodID(type, "<init>", signature), Args(args)));
            }

            internal IntPtr Enum(string enumClass, string constant)
            {
                var type = Own(AndroidJNI.FindClass(Package + enumClass));
                var field = AndroidJNI.GetStaticFieldID(type, constant, "L" + Package + enumClass + ";");
                return Own(AndroidJNI.GetStaticObjectField(type, field));
            }

            /// <summary>Typeface.create(family, NORMAL); null for the system font.</summary>
            internal IntPtr Typeface(string familyName)
            {
                if (familyName == null) return IntPtr.Zero;
                var type = Own(AndroidJNI.FindClass("android/graphics/Typeface"));
                var create = AndroidJNI.GetStaticMethodID(type, "create", "(Ljava/lang/String;I)Landroid/graphics/Typeface;");
                return Own(AndroidJNI.CallStaticObjectMethod(type, create,
                    new[] { new jvalue { l = Java(familyName) }, new jvalue { i = 0 } }));
            }

            private IntPtr Box(string className, string signature, jvalue value)
            {
                var type = Own(AndroidJNI.FindClass(className));
                var valueOf = AndroidJNI.GetStaticMethodID(type, "valueOf", signature);
                return Own(AndroidJNI.CallStaticObjectMethod(type, valueOf, new[] { value }));
            }

            private IntPtr Method(string className, string name, string signature)
            {
                var type = Own(AndroidJNI.FindClass(className));
                return AndroidJNI.GetMethodID(type, name, signature);
            }

            private IntPtr Own(IntPtr reference)
            {
                if (reference != IntPtr.Zero) owned.Add(reference);
                return reference;
            }

            public void Dispose()
            {
                foreach (var reference in owned) AndroidJNI.DeleteLocalRef(reference);
                owned.Clear();
            }
        }

        // The SDK calls these on Android's main thread; ClomniReceiver hands the events to Unity's next frame.
        // AndroidJavaProxy finds each method by the Java interface method's name.

        private sealed class LinkProxy : AndroidJavaProxy
        {
            internal LinkProxy() : base("ai.clomni.messenger.LinkListener") { }

            public bool onLink(string url)
            {
                ClomniReceiver.Post("link\n" + url);
                return true;
            }
        }

        private sealed class UnreadProxy : AndroidJavaProxy
        {
            internal UnreadProxy() : base("ai.clomni.messenger.UnreadCountListener") { }

            public void onUnreadCountChanged(int count) => ClomniReceiver.Post("unreadCountChanged\n" + count);
        }

        private sealed class OpenedProxy : AndroidJavaProxy
        {
            internal OpenedProxy() : base("ai.clomni.messenger.MessengerOpenedListener") { }

            public void onMessengerOpened(string source) =>
                ClomniReceiver.Post(source == null ? "messengerOpened" : "messengerOpened\n" + source);
        }

        private sealed class ClosedProxy : AndroidJavaProxy
        {
            internal ClosedProxy() : base("ai.clomni.messenger.MessengerClosedListener") { }

            public void onMessengerClosed() => ClomniReceiver.Post("messengerClosed");
        }

        /// <summary>ConversationStartedListener.onConversationStarted and FlowCompletedListener.onFlowCompleted.
        /// </summary>
        private sealed class TextProxy : AndroidJavaProxy
        {
            private readonly string eventName;

            internal TextProxy(string listenerInterface, string eventName) : base("ai.clomni.messenger." + listenerInterface)
            {
                this.eventName = eventName;
            }

            public void onConversationStarted(string conversationId) => ClomniReceiver.Post(eventName + "\n" + conversationId);

            public void onFlowCompleted(string flowId) => ClomniReceiver.Post(eventName + "\n" + flowId);
        }
    }
}
#endif
