import type { ClomniEvents, ClomniEventName } from '../index';

type Fake = typeof import('../../test/react-native');
type Package = typeof import('../index');

let rn: Fake;
let Clomni: Package['Clomni'];
let warnings: jest.SpyInstance;
let errors: jest.SpyInstance;

/** A fresh package and native module per test, on `platform` and `architecture`. */
function load(platform: 'ios' | 'android' = 'ios', architecture: 'new' | 'old' | 'missing' = 'new') {
  jest.resetModules();
  rn = require('react-native');
  rn.Platform.OS = platform;
  rn.fake.architecture = architecture;
  Clomni = (require('../index') as Package).default;
}

const calls = () => rn.fake.calls;
const flush = () => new Promise<void>((resolve) => setImmediate(() => resolve()));

beforeEach(() => {
  warnings = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  errors = jest.spyOn(console, 'error').mockImplementation(() => undefined);
  load();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('calls reach the native SDK', () => {
  it('passes every argument, with the defaults filled in', () => {
    Clomni.initialize('app_8x2k0001', 'ios_key');
    Clomni.initialize('app_8x2k0001', 'ios_key', 'eu');
    Clomni.loginUser({ userId: '5', email: 'aysel@example.com', name: 'Aysel' }, 'a1b2');
    Clomni.loginUser({ email: 'aysel@example.com' });
    Clomni.loginUnidentifiedUser();
    Clomni.updateUser({ name: 'Aysel Məmmədova', customAttributes: { plan: 'premium', rides: 18 } });
    Clomni.updateUser({ language: 'az' });
    Clomni.setLogLevel('debug');
    Clomni.setTypeface('Montserrat');
    Clomni.setTypeface(null);
    Clomni.present();
    Clomni.present('profile_support');
    Clomni.presentNewConversation();
    Clomni.presentNewConversation('help');
    Clomni.presentConversation('conv_5521');
    Clomni.dismiss();
    Clomni.startFlow('payment_failed');
    Clomni.startFlow('ride_problem', { ride_id: 'R-1042', amount: 2.4, tags: ['late'], extra: null },
      { openMessenger: true, source: 'ride_detail' });
    Clomni.setLauncherVisible(true);
    Clomni.setBottomPadding(56);
    Clomni.setDeviceToken('ab01');
    Clomni.logout();
    expect(calls()).toEqual([
      ['setup', 'app_8x2k0001', 'ios_key', 'eu'],
      ['setup', 'app_8x2k0001', 'ios_key', 'eu'],
      ['loginUser', { userId: '5', email: 'aysel@example.com', name: 'Aysel' }, 'a1b2'],
      ['loginUser', { email: 'aysel@example.com' }, null],
      ['loginUnidentifiedUser'],
      ['updateUser', 'Aysel Məmmədova', null, { plan: 'premium', rides: 18 }],
      ['updateUser', null, 'az', null],
      ['setLogLevel', 'debug'],
      ['setTypeface', 'Montserrat'],
      ['setTypeface', null],
      ['present', null],
      ['present', 'profile_support'],
      ['presentNewConversation', null],
      ['presentNewConversation', 'help'],
      ['presentConversation', 'conv_5521'],
      ['dismiss'],
      ['startFlow', 'payment_failed', {}, false, null],
      ['startFlow', 'ride_problem', { ride_id: 'R-1042', amount: 2.4, tags: ['late'], extra: null }, true, 'ride_detail'],
      ['setLauncherVisible', true],
      ['setBottomPadding', 56],
      ['setDeviceToken', 'ab01'],
      ['logout'],
    ]);
    expect(warnings).not.toHaveBeenCalled();
  });

  it('refuses what JSON cannot carry, and says so', () => {
    Clomni.startFlow('ride_problem', { at: new Date() as never });
    Clomni.startFlow('ride_problem', { amount: Number.NaN });
    Clomni.startFlow('ride_problem', { nested: { call: (() => 1) as never } });
    Clomni.updateUser({ customAttributes: { at: new Date() as never } });
    Clomni.updateUser({});
    expect(calls()).toEqual([]);
    expect(errors).toHaveBeenCalledWith('[Clomni] startFlow: data holds something JSON cannot carry');
    expect(errors).toHaveBeenCalledWith('[Clomni] updateUser: customAttributes hold something JSON cannot carry');
    expect(warnings).toHaveBeenCalledWith('[Clomni] updateUser: nothing to change');
  });

  it('finds the module once, through the old architecture too', () => {
    Clomni.dismiss();
    Clomni.dismiss();
    expect(rn.fake.lookups).toBe(1);

    load('android', 'old');
    Clomni.present('menu');
    expect(calls()).toEqual([['present', 'menu']]);
  });

  it('says how to fix a build without the module, but importing it does not throw', () => {
    expect(() => load('ios', 'missing')).not.toThrow();
    expect(() => Clomni.present()).toThrow(/native module is not in this app's build.*Expo Go cannot load it/);
    expect(Clomni.isClomniPush({ clomni: '1' })).toBe(true);
  });
});

describe('push', () => {
  const clomniPush = { clomni: '1', type: 'message', conversation_id: 'conv_5521', title: 'Leyla · Apar', body: 'Salam' };
  const ownPush = { order_id: '7', aps: { alert: 'Sifarişiniz yoldadır' } };

  it('tells Clomni pushes from the app’s own', () => {
    expect(Clomni.isClomniPush(clomniPush)).toBe(true);
    expect(Clomni.isClomniPush(ownPush)).toBe(false);
    expect(Clomni.isClomniPush({ clomni: 1 })).toBe(false);
    expect(Clomni.isClomniPush(null)).toBe(false);
    expect(Clomni.isClomniPush(undefined)).toBe(false);
  });

  it('opens a Clomni push and leaves the app’s own alone', () => {
    expect(Clomni.handlePush(ownPush)).toBe(false);
    expect(calls()).toEqual([]);
    expect(Clomni.handlePush(clomniPush)).toBe(true);
    expect(calls()).toEqual([['handlePush', clomniPush]]);
  });

  it('on iOS asks the SDK whether to show a Clomni push in the foreground', () => {
    expect(Clomni.shouldShowForeground(ownPush)).toBe(true);
    expect(Clomni.shouldShowForeground(clomniPush)).toBe(true);
    rn.fake.messengerOpen = true;
    expect(Clomni.shouldShowForeground(clomniPush)).toBe(false);
    expect(calls()).toEqual([['shouldShowForeground', clomniPush], ['shouldShowForeground', clomniPush]]);
  });

  it('on Android shows foreground pushes, and takes the notification icon', () => {
    load('android');
    rn.fake.messengerOpen = true;
    expect(Clomni.shouldShowForeground(clomniPush)).toBe(true);
    Clomni.setNotificationIcon('ic_stat_clomni');
    expect(calls()).toEqual([['setNotificationIcon', 'ic_stat_clomni']]);

    load('ios');
    Clomni.setNotificationIcon('ic_stat_clomni');
    expect(calls()).toEqual([]);
    expect(warnings).toHaveBeenCalledWith('[Clomni] setNotificationIcon is Android only');
  });
});

describe.each(['new', 'old'] as const)('events, %s architecture', (architecture) => {
  beforeEach(() => load('ios', architecture));

  function heard<Name extends ClomniEventName>(name: Name): { values: unknown[]; remove(): void } {
    const values: unknown[] = [];
    const listener = ((...args: unknown[]) => values.push(args.length ? args[0] : 'called')) as ClomniEvents[Name];
    const subscription = Clomni.addEventListener(name, listener);
    return { values, remove: () => subscription.remove() };
  }

  it('hands each listener its own event and value', async () => {
    const opened = heard('messengerOpened');
    const closed = heard('messengerClosed');
    const started = heard('conversationStarted');
    const finished = heard('flowCompleted');
    rn.fake.emit({ name: 'messengerOpened', text: 'profile_support' });
    rn.fake.emit({ name: 'messengerOpened' });
    rn.fake.emit({ name: 'conversationStarted', text: 'conv_new' });
    rn.fake.emit({ name: 'flowCompleted', text: 'flow_42' });
    rn.fake.emit({ name: 'messengerClosed' });
    rn.fake.emit({ name: 'somethingNew', text: 'ignored' });
    expect(opened.values).toEqual(['profile_support', null]);
    expect(closed.values).toEqual(['called']);
    expect(started.values).toEqual(['conv_new']);
    expect(finished.values).toEqual(['flow_42']);

    opened.remove();
    opened.remove();
    rn.fake.emit({ name: 'messengerOpened', text: 'again' });
    expect(opened.values).toEqual(['profile_support', null]);
  });

  it('gives the unread count at once, then each change', async () => {
    rn.fake.unreadCount = 2;
    const unread = heard('unreadCountChanged');
    await flush();
    rn.fake.emit({ name: 'unreadCountChanged', count: 3 });
    rn.fake.emit({ name: 'unreadCountChanged' });
    expect(unread.values).toEqual([2, 3, 0]);

    // Removed before the native answer came: nothing.
    const late = heard('unreadCountChanged');
    late.remove();
    await flush();
    expect(late.values).toEqual([]);
  });
});
