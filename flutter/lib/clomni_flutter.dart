/// The Clomni Messenger in a Flutter app: the native iOS and Android SDKs, which draw the messenger natively, behind
/// one Dart API (brief 8 · 9). Nothing of Clomni shows until the app asks.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's logged-in user, for [Clomni.loginUser]. Clomni knows the user by [userId], else by [email].
@immutable
class ClomniUser {
  const ClomniUser({this.userId, this.email, this.phone, this.name});

  final String? userId;
  final String? email;
  final String? phone;
  final String? name;

  Map<String, String> toMap() => {
        if (userId != null) 'userId': userId!,
        if (email != null) 'email': email!,
        if (phone != null) 'phone': phone!,
        if (name != null) 'name': name!,
      };
}

/// How much the SDK writes to the system log; `none` writes nothing, the default is `warning`.
enum ClomniLogLevel { none, error, warning, info, debug }

/// The Clomni Messenger. Every call goes to the native SDK of the platform.
class Clomni {
  Clomni._();

  @visibleForTesting
  static const MethodChannel methods = MethodChannel('ai.clomni.flutter/methods');

  @visibleForTesting
  static const EventChannel events = EventChannel('ai.clomni.flutter/events');

  static Stream<Map<Object?, Object?>>? _events;

  /// The SDK's events, `{name, count?, text?}`, shared by every stream below.
  static Stream<Map<Object?, Object?>> get _nativeEvents =>
      _events ??= events.receiveBroadcastStream().map((event) => event as Map<Object?, Object?>);

  @visibleForTesting
  static void resetForTesting() => _events = null;

  /// Prepares the connection and push; adds nothing to the app's screens. Call it once, at the app's start.
  static Future<void> initialize(String appId, String apiKey, {String region = 'eu'}) =>
      methods.invokeMethod('setup', {'appId': appId, 'apiKey': apiKey, 'region': region});

  /// The app's logged-in user. [userHash] is hex(HMAC-SHA256(identity_secret, userId)), computed on the app's server;
  /// identity_secret never goes into the app.
  static Future<void> loginUser(ClomniUser user, {String? userHash}) =>
      methods.invokeMethod('loginUser', {'user': user.toMap(), 'userHash': userHash});

  /// An anonymous visitor, the same one on this device until [logout].
  static Future<void> loginUnidentifiedUser() => methods.invokeMethod('loginUnidentifiedUser');

  /// Changes only what is given; [customAttributes] are merged with the user's. [language] is "az", "en" or "ru".
  static Future<void> updateUser({String? name, String? language, Map<String, Object?>? customAttributes}) async {
    if (customAttributes != null && !_isJson(customAttributes)) {
      return _log('updateUser: customAttributes hold something JSON cannot carry');
    }
    if (name == null && language == null && customAttributes == null) return _log('updateUser: nothing to change');
    await methods.invokeMethod('updateUser', {'name': name, 'language': language, 'customAttributes': customAttributes});
  }

  /// Ends the session and deletes the messenger's data on this device; call it when the app's user logs out.
  static Future<void> logout() => methods.invokeMethod('logout');

  static Future<void> setLogLevel(ClomniLogLevel level) => methods.invokeMethod('setLogLevel', level.name);

  /// A font family the platform knows (iOS: in UIAppFonts; Android: res/font) for the messenger's texts; null is the
  /// system font.
  static Future<void> setTypeface(String? familyName) => methods.invokeMethod('setTypeface', familyName);

  /// Home. [source] says where in the app (for example "profile_support").
  static Future<void> present({String? source}) => methods.invokeMethod('present', source);

  /// Straight into a new conversation, with the inbox's first flow.
  static Future<void> presentNewConversation({String? source}) =>
      methods.invokeMethod('presentNewConversation', source);

  static Future<void> presentConversation(String conversationId) =>
      methods.invokeMethod('presentConversation', conversationId);

  static Future<void> dismiss() => methods.invokeMethod('dismiss');

  /// Starts the flow bound to an app event (for example "ride_problem") in a new conversation; its texts can use
  /// [data] as `{{data.ride_id}}`. With [openMessenger] it opens on screen. Nothing happens when no flow is bound.
  static Future<void> startFlow(String event,
      {Map<String, Object?> data = const {}, bool openMessenger = false, String? source}) async {
    if (!_isJson(data)) return _log('startFlow: data holds something JSON cannot carry');
    await methods.invokeMethod(
        'startFlow', {'event': event, 'data': data, 'openMessenger': openMessenger, 'source': source});
  }

  /// The floating button: off by default, and the panel can turn it on too. The app's choice wins.
  static Future<void> setLauncherVisible(bool visible) => methods.invokeMethod('setLauncherVisible', visible);

  /// Lifts the launcher above the app's bottom bar (points on iOS, dp on Android).
  static Future<void> setBottomPadding(double padding) => methods.invokeMethod('setBottomPadding', padding);

  /// The push token: the APNs device token as hex on iOS, the FCM token on Android.
  static Future<void> setDeviceToken(String token) => methods.invokeMethod('setDeviceToken', token);

  /// Whether a push is Clomni's; the app's own pushes are the app's to handle.
  static bool isClomniPush(Map<String, Object?>? data) => data != null && data['clomni'] == '1';

  /// A Clomni push, as each platform delivers it. iOS: a tap on its notification opens the conversation. Android:
  /// the FCM data message as it arrives; the SDK shows it as a notification whose tap opens the conversation. false
  /// for the app's own pushes.
  static Future<bool> handlePush(Map<String, Object?>? data) async {
    if (!isClomniPush(data)) return false;
    await methods.invokeMethod('handlePush', _strings(data!));
    return true;
  }

  /// iOS: for a push that arrives while the app is open, false for a Clomni push while the messenger is open (it shows
  /// the message itself). Android shows or hides its notifications itself: always true there.
  static Future<bool> shouldShowForeground(Map<String, Object?>? data) async {
    if (!isClomniPush(data) || defaultTargetPlatform != TargetPlatform.iOS) return true;
    return await methods.invokeMethod<bool>('shouldShowForeground', _strings(data!)) ?? true;
  }

  /// Android: the small icon of Clomni's notifications, a drawable's name. Nothing on iOS.
  static Future<void> setNotificationIcon(String name) async {
    if (defaultTargetPlatform != TargetPlatform.android) return _log('setNotificationIcon is Android only');
    await methods.invokeMethod('setNotificationIcon', name);
  }

  /// The unread count for the app's own badge: the current one at once, then every change.
  static Stream<int> get unreadCountStream => Stream<int>.multi((controller) {
        final subscription = _named('unreadCountChanged').listen((event) => controller.add(_count(event)));
        methods.invokeMethod<int>('getUnreadCount').then((count) {
          if (count != null && !controller.isClosed) controller.add(count);
        }, onError: (Object _) {});
        controller.onCancel = subscription.cancel;
      });

  /// The messenger opened, with the source given to [present].
  static Stream<String?> get onMessengerOpened => _named('messengerOpened').map((event) => event['text'] as String?);

  static Stream<void> get onMessengerClosed => _named('messengerClosed').map((_) {});

  /// A new conversation, with its id.
  static Stream<String> get onConversationStarted =>
      _named('conversationStarted').map((event) => event['text'] as String? ?? '');

  /// A flow reached its end, with the flow's id.
  static Stream<String> get onFlowCompleted => _named('flowCompleted').map((event) => event['text'] as String? ?? '');

  static Stream<Map<Object?, Object?>> _named(String name) => _nativeEvents.where((event) => event['name'] == name);

  static int _count(Map<Object?, Object?> event) => (event['count'] as num?)?.toInt() ?? 0;

  /// Push data as the platforms carry it: text values (FCM data has only those; APNs' nested aps stays out).
  static Map<String, String> _strings(Map<String, Object?> data) => {
        for (final entry in data.entries)
          if (entry.value is String || entry.value is num || entry.value is bool) entry.key: '${entry.value}',
      };

  static bool _isJson(Object? value, [int depth = 0]) {
    if (depth > 32) return false;
    if (value == null || value is String || value is bool) return true;
    if (value is num) return value.isFinite;
    if (value is List) return value.every((item) => _isJson(item, depth + 1));
    if (value is Map) return value.keys.every((key) => key is String) && value.values.every((item) => _isJson(item, depth + 1));
    return false;
  }

  static void _log(String message) => debugPrint('[Clomni] $message');
}
