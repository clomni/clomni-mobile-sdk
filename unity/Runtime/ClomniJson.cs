using System;
using System.Collections;
using System.Globalization;
using System.Text;

namespace ClomniMessenger
{
    /// <summary>
    /// The values custom attributes and flow data may hold: null, string, bool, numbers, and dictionaries and lists of
    /// them. iOS receives them as JSON text; Android as Java maps, lists and boxes.
    /// </summary>
    internal static class ClomniJson
    {
        internal static bool IsJson(object value, int depth = 0)
        {
            if (depth > 32) return false;
            switch (value)
            {
                case null:
                case string _:
                case bool _:
                    return true;
                case float f:
                    return !float.IsNaN(f) && !float.IsInfinity(f);
                case double d:
                    return !double.IsNaN(d) && !double.IsInfinity(d);
                case IDictionary map:
                    foreach (DictionaryEntry entry in map)
                    {
                        if (!(entry.Key is string) || !IsJson(entry.Value, depth + 1)) return false;
                    }
                    return true;
                case IEnumerable list:
                    foreach (var item in list)
                    {
                        if (!IsJson(item, depth + 1)) return false;
                    }
                    return true;
                default:
                    return IsInteger(value) || value is decimal;
            }
        }

        internal static bool IsInteger(object value) =>
            value is int || value is long || value is short || value is byte || value is sbyte || value is uint ||
            value is ushort || value is ulong;

        /// <summary>JSON text of a value that passed <see cref="IsJson"/>.</summary>
        internal static string Write(object value)
        {
            var text = new StringBuilder();
            Write(value, text);
            return text.ToString();
        }

        private static void Write(object value, StringBuilder text)
        {
            switch (value)
            {
                case null:
                    text.Append("null");
                    break;
                case string s:
                    WriteString(s, text);
                    break;
                case bool b:
                    text.Append(b ? "true" : "false");
                    break;
                case IDictionary map:
                    text.Append('{');
                    var first = true;
                    foreach (DictionaryEntry entry in map)
                    {
                        if (!first) text.Append(',');
                        first = false;
                        WriteString((string)entry.Key, text);
                        text.Append(':');
                        Write(entry.Value, text);
                    }
                    text.Append('}');
                    break;
                case IEnumerable list:
                    text.Append('[');
                    var firstItem = true;
                    foreach (var item in list)
                    {
                        if (!firstItem) text.Append(',');
                        firstItem = false;
                        Write(item, text);
                    }
                    text.Append(']');
                    break;
                case float f:
                    text.Append(f.ToString("R", CultureInfo.InvariantCulture));
                    break;
                case double d:
                    text.Append(d.ToString("R", CultureInfo.InvariantCulture));
                    break;
                default:
                    text.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
                    break;
            }
        }

        private static void WriteString(string value, StringBuilder text)
        {
            text.Append('"');
            foreach (var c in value)
            {
                switch (c)
                {
                    case '"': text.Append("\\\""); break;
                    case '\\': text.Append("\\\\"); break;
                    case '\n': text.Append("\\n"); break;
                    case '\r': text.Append("\\r"); break;
                    case '\t': text.Append("\\t"); break;
                    default:
                        if (c < ' ') text.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else text.Append(c);
                        break;
                }
            }
            text.Append('"');
        }
    }
}
