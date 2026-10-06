namespace ClomniMessenger
{
    /// <summary>The app's logged-in user, for <see cref="Clomni.LoginUser"/>. Clomni knows the user by
    /// <c>UserId</c>, else by <c>Email</c>.</summary>
    public sealed class ClomniUser
    {
        public string UserId { get; set; }
        public string Email { get; set; }
        public string Phone { get; set; }
        public string Name { get; set; }
    }

    /// <summary><c>None</c> writes nothing; the default is <c>Warning</c>.</summary>
    public enum ClomniLogLevel
    {
        None,
        Error,
        Warning,
        Info,
        Debug,
    }

    /// <summary>For <see cref="Clomni.SetTheme"/>: light, dark, or as the system is.</summary>
    public enum ClomniThemeMode
    {
        Light,
        Dark,
        System,
    }
}
