import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Dart layer over a mocked native side: what reaches the method channel, and what the event channel's events
/// become.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late int unreadCount;
  late bool messengerOpen;
  MockStreamHandlerEventSink? sink;
  final logged = <String>[];

  setUp(() {
    calls = [];
    unreadCount = 0;
    messengerOpen = false;
    logged.clear();
    Clomni.resetForTesting();
    debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
    messenger.setMockMethodCallHandler(Clomni.methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getUnreadCount':
          return unreadCount;
        case 'shouldShowForeground':
          return !messengerOpen;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      Clomni.events,
      MockStreamHandler.inline(onListen: (arguments, events) => sink = events, onCancel: (_) => sink = null),
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    debugPrint = debugPrintThrottled;
  });

  List<Object?> sent() => calls.map((call) => [call.method, call.arguments]).toList();

  group('calls reach the native SDK', () {
    test('with every argument and the defaults filled in', () async {
      await Clomni.initialize('app_8x2k0001', 'android_key');
      await Clomni.loginUser(const ClomniUser(userId: '5', email: 'aysel@example.com', name: 'Aysel'), userHash: 'a1b2');
      await Clomni.loginUser(const ClomniUser(email: 'aysel@example.com'));
      await Clomni.loginUnidentifiedUser();
      await Clomni.updateUser(name: 'Aysel Məmmədova', customAttributes: {'plan': 'premium', 'rides': 18});
      await Clomni.setLogLevel(ClomniLogLevel.debug);
      await Clomni.setTypeface('Montserrat');
      await Clomni.setTypeface(null);
      await Clomni.present();
      await Clomni.present(source: 'profile_support');
      await Clomni.presentNewConversation(source: 'help');
      await Clomni.presentConversation('conv_5521');
      await Clomni.dismiss();
      await Clomni.startFlow('payment_failed');
      await Clomni.startFlow('ride_problem',
          data: {'ride_id': 'R-1042', 'amount': 2.4, 'tags': ['late'], 'extra': null},
          openMessenger: true, source: 'ride_detail');
      await Clomni.setLauncherVisible(true);
      await Clomni.setBottomPadding(56);
      await Clomni.setDeviceToken('fcm-token');
      await Clomni.logout();
      expect(sent(), [
        ['setup', {'appId': 'app_8x2k0001', 'apiKey': 'android_key', 'region': 'eu'}],
        ['loginUser', {'user': {'userId': '5', 'email': 'aysel@example.com', 'name': 'Aysel'}, 'userHash': 'a1b2'}],
        ['loginUser', {'user': {'email': 'aysel@example.com'}, 'userHash': null}],
        ['loginUnidentifiedUser', null],
        ['updateUser', {'name': 'Aysel Məmmədova', 'language': null, 'customAttributes': {'plan': 'premium', 'rides': 18}}],
        ['setLogLevel', 'debug'],
        ['setTypeface', 'Montserrat'],
        ['setTypeface', null],
        ['present', null],
        ['present', 'profile_support'],
        ['presentNewConversation', 'help'],
        ['presentConversation', 'conv_5521'],
        ['dismiss', null],
        ['startFlow', {'event': 'payment_failed', 'data': {}, 'openMessenger': false, 'source': null}],
        ['startFlow', {
          'event': 'ride_problem',
          'data': {'ride_id': 'R-1042', 'amount': 2.4, 'tags': ['late'], 'extra': null},
          'openMessenger': true,
          'source': 'ride_detail'
        }],
        ['setLauncherVisible', true],
        ['setBottomPadding', 56.0],
        ['setDeviceToken', 'fcm-token'],
        ['logout', null],
      ]);
      expect(logged, isEmpty);
    });

    test('refuses what JSON cannot carry, and says so', () async {
      await Clomni.startFlow('ride_problem', data: {'at': DateTime(2026)});
      await Clomni.startFlow('ride_problem', data: {'amount': double.nan});
      await Clomni.updateUser(customAttributes: {'nested': {1: 'not a string key'}});
      await Clomni.updateUser();
      expect(calls, isEmpty);
      expect(logged, [
        '[Clomni] startFlow: data holds something JSON cannot carry',
        '[Clomni] startFlow: data holds something JSON cannot carry',
        '[Clomni] updateUser: customAttributes hold something JSON cannot carry',
        '[Clomni] updateUser: nothing to change',
      ]);
    });
  });

  group('push', () {
    const clomniPush = {'clomni': '1', 'type': 'message', 'conversation_id': 'conv_5521', 'unread_total': 2,
      'aps': {'alert': 'Salam'}};
    const ownPush = {'order_id': '7'};

    test("tells Clomni's pushes from the app's own", () {
      expect(Clomni.isClomniPush(clomniPush), isTrue);
      expect(Clomni.isClomniPush(ownPush), isFalse);
      expect(Clomni.isClomniPush({'clomni': 1}), isFalse);
      expect(Clomni.isClomniPush(null), isFalse);
    });

    test("hands over Clomni's, as text values, and leaves the app's own alone", () async {
      expect(await Clomni.handlePush(ownPush), isFalse);
      expect(calls, isEmpty);
      expect(await Clomni.handlePush(clomniPush), isTrue);
      expect(sent(), [
        ['handlePush', {'clomni': '1', 'type': 'message', 'conversation_id': 'conv_5521', 'unread_total': '2'}]
      ]);
    });

    test('asks the iOS SDK whether to show a push in the foreground; Android shows its own', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await Clomni.shouldShowForeground(ownPush), isTrue);
      expect(await Clomni.shouldShowForeground(clomniPush), isTrue);
      messengerOpen = true;
      expect(await Clomni.shouldShowForeground(clomniPush), isFalse);
      expect(calls.map((call) => call.method), ['shouldShowForeground', 'shouldShowForeground']);

      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await Clomni.shouldShowForeground(clomniPush), isTrue);
      await Clomni.setNotificationIcon('ic_stat_clomni');
      expect(sent(), [
        ['setNotificationIcon', 'ic_stat_clomni']
      ]);

      calls.clear();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await Clomni.setNotificationIcon('ic_stat_clomni');
      expect(calls, isEmpty);
      expect(logged, ['[Clomni] setNotificationIcon is Android only']);
    });
  });

  group('events', () {
    test('each stream hears its own event', () async {
      final opened = <String?>[];
      final closed = <int>[];
      final started = <String>[];
      final finished = <String>[];
      final subscriptions = [
        Clomni.onMessengerOpened.listen(opened.add),
        Clomni.onMessengerClosed.listen((_) => closed.add(1)),
        Clomni.onConversationStarted.listen(started.add),
        Clomni.onFlowCompleted.listen(finished.add),
      ];
      await pumpEventQueue();
      sink!.success({'name': 'messengerOpened', 'text': 'profile_support'});
      sink!.success({'name': 'messengerOpened'});
      sink!.success({'name': 'conversationStarted', 'text': 'conv_new'});
      sink!.success({'name': 'flowCompleted', 'text': 'flow_42'});
      sink!.success({'name': 'messengerClosed'});
      sink!.success({'name': 'somethingNew', 'text': 'ignored'});
      await pumpEventQueue();
      expect(opened, ['profile_support', null]);
      expect(closed, [1]);
      expect(started, ['conv_new']);
      expect(finished, ['flow_42']);

      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await pumpEventQueue();
      expect(sink, isNull, reason: 'the native side stops sending when nobody listens');
    });

    test('unreadCountStream gives the current count at once, then each change', () async {
      unreadCount = 2;
      final counts = <int>[];
      final subscription = Clomni.unreadCountStream.listen(counts.add);
      await pumpEventQueue();
      sink!.success({'name': 'unreadCountChanged', 'count': 3});
      sink!.success({'name': 'unreadCountChanged'});
      await pumpEventQueue();
      expect(counts, [2, 3, 0]);
      await subscription.cancel();
    });
  });
}
