import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A ride app's profile screen: its own buttons open the messenger; there is no Clomni element of its own.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // From Clomni: Channels → Mobile app. The API key of this platform.
  Clomni.initialize('app_xxxxxxxx', defaultTargetPlatform == TargetPlatform.iOS ? 'ios_xxxxxxxx' : 'android_xxxxxxxx');
  if (kDebugMode) Clomni.setLogLevel(ClomniLogLevel.debug);
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(home: ProfileScreen());
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loggedIn = false;
  bool _launcher = false;

  Future<void> _logIn() async {
    // userHash is hex(HMAC-SHA256(identity_secret, user_id)), made on the app's server; identity_secret never goes
    // into the app.
    await Clomni.loginUser(const ClomniUser(userId: '5', email: 'aysel@example.com', name: 'Aysel'), userHash: null);
    await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});
    setState(() => _loggedIn = true);
  }

  Future<void> _logOut() async {
    // Without this the next user of the phone sees Aysel's conversations.
    await Clomni.logout();
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apar')),
      body: ListView(
        children: [
          ListTile(
            title: Text(_loggedIn ? 'Çıxış' : 'Daxil ol: Aysel'),
            onTap: _loggedIn ? _logOut : _logIn,
          ),
          ListTile(
            title: const Text('Problem bildir'),
            subtitle: const Text('Gənclik → 28 May · 2.40 ₼'),
            // A button with context: the flow bound to "ride_problem" gets the ride.
            onTap: () => Clomni.startFlow('ride_problem',
                data: {'ride_id': 'R-1042', 'amount': 2.40}, openMessenger: true, source: 'ride_detail'),
          ),
          ListTile(
            title: const Text('Dəstək'),
            // The unread count on the app's own row.
            trailing: StreamBuilder<int>(
              stream: Clomni.unreadCountStream,
              builder: (context, snapshot) {
                final unread = snapshot.data ?? 0;
                return unread > 0 ? Badge(label: Text('$unread')) : const SizedBox.shrink();
              },
            ),
            onTap: () => Clomni.present(source: 'profile_support'),
          ),
          SwitchListTile(
            title: const Text('Üzən düymə'),
            value: _launcher,
            onChanged: (value) {
              Clomni.setLauncherVisible(value);
              setState(() => _launcher = value);
            },
          ),
        ],
      ),
    );
  }
}
