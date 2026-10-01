// A stand-in for react-native in the jest tests: the native module records its calls, and the test decides the
// platform, the architecture (New: TurboModule + EventEmitter; old: NativeModules + NativeEventEmitter) and events.
import type { NativeEvent, Spec } from '../src/NativeClomni';

type Listener = (event: NativeEvent) => void;

export const fake = {
  architecture: 'new' as 'new' | 'old' | 'missing',
  calls: [] as unknown[][],
  unreadCount: 0,
  messengerOpen: false,
  turboListeners: new Set<Listener>(),
  legacyListeners: new Set<Listener>(),
  lookups: 0,

  /** An event from the SDK, through whichever channel the architecture has. */
  emit(event: NativeEvent) {
    const listeners = this.architecture === 'new' ? this.turboListeners : this.legacyListeners;
    listeners.forEach((listener) => listener(event));
  },
};

function record(name: string) {
  return (...args: unknown[]) => {
    fake.calls.push([name, ...args]);
  };
}

const methods = {
  setup: record('setup'),
  loginUser: record('loginUser'),
  loginUnidentifiedUser: record('loginUnidentifiedUser'),
  updateUser: record('updateUser'),
  logout: record('logout'),
  setLogLevel: record('setLogLevel'),
  setTypeface: record('setTypeface'),
  present: record('present'),
  presentNewConversation: record('presentNewConversation'),
  presentConversation: record('presentConversation'),
  dismiss: record('dismiss'),
  startFlow: record('startFlow'),
  setLauncherVisible: record('setLauncherVisible'),
  setBottomPadding: record('setBottomPadding'),
  setDeviceToken: record('setDeviceToken'),
  handlePush: record('handlePush'),
  shouldShowForeground(data: object): boolean {
    fake.calls.push(['shouldShowForeground', data]);
    return !fake.messengerOpen;
  },
  setNotificationIcon: record('setNotificationIcon'),
  getUnreadCount(): Promise<number> {
    return Promise.resolve(fake.unreadCount);
  },
  addListener: record('addListener'),
  removeListeners: record('removeListeners'),
};

const turboModule = {
  ...methods,
  onEvent(listener: Listener) {
    fake.turboListeners.add(listener);
    return { remove: () => fake.turboListeners.delete(listener) };
  },
} as unknown as Spec;

const legacyModule = methods as unknown as Spec;

export const Platform = { OS: 'ios' as 'ios' | 'android' };

export const TurboModuleRegistry = {
  get(name: string): Spec | null {
    fake.lookups += 1;
    return name === 'Clomni' && fake.architecture === 'new' ? turboModule : null;
  },
  getEnforcing(name: string): Spec {
    const module = TurboModuleRegistry.get(name);
    if (!module) throw new Error(`TurboModuleRegistry.getEnforcing(...): '${name}' could not be found.`);
    return module;
  },
};

export const NativeModules = {
  get Clomni(): Spec | undefined {
    return fake.architecture === 'old' ? legacyModule : undefined;
  },
};

export class NativeEventEmitter {
  constructor(readonly module?: unknown) {}

  addListener(eventType: string, listener: Listener) {
    if (eventType !== 'ClomniEvent') throw new Error(`unexpected event ${eventType}`);
    fake.legacyListeners.add(listener);
    return { remove: () => fake.legacyListeners.delete(listener) };
  }
}
