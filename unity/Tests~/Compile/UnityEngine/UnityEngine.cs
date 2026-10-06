// Signatures only, as UnityEngine 2021.3 declares them: what the package and its samples use. Nothing here runs.
using System;

namespace UnityEngine
{
    public class Object
    {
        public static void DontDestroyOnLoad(Object target) => throw null;
        public static bool operator ==(Object x, Object y) => throw null;
        public static bool operator !=(Object x, Object y) => throw null;
        public override bool Equals(object other) => throw null;
        public override int GetHashCode() => throw null;
    }

    public class Component : Object { }

    public class Behaviour : Component { }

    public class MonoBehaviour : Behaviour { }

    public sealed class GameObject : Object
    {
        public GameObject(string name) => throw null;
        public T AddComponent<T>() where T : Component => throw null;
    }

    [AttributeUsage(AttributeTargets.Field)]
    public sealed class SerializeField : Attribute { }

    public static class Debug
    {
        public static void Log(object message) => throw null;
        public static void LogWarning(object message) => throw null;
        public static void LogError(object message) => throw null;
    }

    public enum RuntimePlatform
    {
        OSXEditor = 0,
        OSXPlayer = 1,
        WindowsPlayer = 2,
        WindowsEditor = 7,
        IPhonePlayer = 8,
        Android = 11,
        LinuxPlayer = 13,
        LinuxEditor = 16,
        WebGLPlayer = 17,
    }

    public static class Application
    {
        public static RuntimePlatform platform => throw null;
        public static void OpenURL(string url) => throw null;
    }

    public static class Screen
    {
        public static int width => throw null;
        public static int height => throw null;
    }

    public struct Rect
    {
        public Rect(float x, float y, float width, float height) => throw null;
    }

    public sealed class GUIStyle
    {
        public int fontSize { get => throw null; set => throw null; }
    }

    public sealed class GUISkin : Object
    {
        public GUIStyle button { get => throw null; set => throw null; }
    }

    public class GUI
    {
        public static GUISkin skin { get => throw null; set => throw null; }
    }

    public sealed class GUILayoutOption { }

    public class GUILayout
    {
        public static bool Button(string text, params GUILayoutOption[] options) => throw null;
        public static GUILayoutOption Height(float height) => throw null;
        public static void BeginArea(Rect screenRect) => throw null;
        public static void EndArea() => throw null;
    }

    public struct jvalue
    {
        public bool z;
        public sbyte b;
        public char c;
        public short s;
        public int i;
        public long j;
        public float f;
        public double d;
        public IntPtr l;
    }

    public class AndroidJavaObject : IDisposable
    {
        public AndroidJavaObject(string className, params object[] args) => throw null;
        public IntPtr GetRawObject() => throw null;
        public ReturnType Call<ReturnType>(string methodName, params object[] args) => throw null;
        public ReturnType CallStatic<ReturnType>(string methodName, params object[] args) => throw null;
        public FieldType GetStatic<FieldType>(string fieldName) => throw null;
        public void Dispose() => throw null;
    }

    public class AndroidJavaClass : AndroidJavaObject
    {
        public AndroidJavaClass(string className) : base(className) => throw null;
        public IntPtr GetRawClass() => throw null;
    }

    public class AndroidJavaProxy
    {
        public AndroidJavaProxy(string javaInterface) => throw null;
    }

    public static class AndroidJNIHelper
    {
        public static IntPtr CreateJavaProxy(AndroidJavaProxy proxy) => throw null;
    }

    public static class AndroidJNI
    {
        public static IntPtr FindClass(string name) => throw null;
        public static IntPtr GetMethodID(IntPtr clazz, string name, string sig) => throw null;
        public static IntPtr GetStaticMethodID(IntPtr clazz, string name, string sig) => throw null;
        public static IntPtr GetStaticFieldID(IntPtr clazz, string name, string sig) => throw null;
        public static IntPtr GetStaticObjectField(IntPtr clazz, IntPtr fieldID) => throw null;
        public static IntPtr NewObject(IntPtr clazz, IntPtr methodID, jvalue[] args) => throw null;
        public static IntPtr NewString(string chars) => throw null;
        public static void CallStaticVoidMethod(IntPtr clazz, IntPtr methodID, jvalue[] args) => throw null;
        public static bool CallStaticBooleanMethod(IntPtr clazz, IntPtr methodID, jvalue[] args) => throw null;
        public static IntPtr CallStaticObjectMethod(IntPtr clazz, IntPtr methodID, jvalue[] args) => throw null;
        public static IntPtr CallObjectMethod(IntPtr obj, IntPtr methodID, jvalue[] args) => throw null;
        public static bool CallBooleanMethod(IntPtr obj, IntPtr methodID, jvalue[] args) => throw null;
        public static void DeleteLocalRef(IntPtr obj) => throw null;
        public static IntPtr ExceptionOccurred() => throw null;
        public static void ExceptionClear() => throw null;
        public static void ExceptionDescribe() => throw null;
    }
}

namespace UnityEngine
{
    public class AndroidJavaException : System.Exception
    {
        public AndroidJavaException(string message) : base(message) { }
    }
}
