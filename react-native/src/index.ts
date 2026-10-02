import { NativeEventEmitter, NativeModules, Platform, TurboModuleRegistry } from 'react-native';
import type { NativeEvent, Spec } from './NativeClomni';

/** The app's logged-in user, for `Clomni.loginUser`. Clomni knows the user by `userId`, else by `email`. */
export type ClomniUser = {
  userId?: string;
  email?: string;
  phone?: string;
  name?: string;
};

/** For `Clomni.updateUser`: only what is given changes; `customAttributes` are merged with the user's. */
export type ClomniUserUpdate = {
  name?: string;
  /** "az", "en" or "ru". */
  language?: string;
  customAttributes?: Record<string, JsonValue>;
};

export type JsonValue = string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

/** `none` writes nothing; the default is `warning`. */
export type ClomniLogLevel = 'none' | 'error' | 'warning' | 'info' | 'debug';

/** For `Clomni.setTheme`: light, dark, or as the system is. */
export type ClomniThemeMode = 'light' | 'dark' | 'system';

/** For `Clomni.setTheme`: what is left out (or null) stays the panel's. */
export type ClomniTheme = {
  /** "#RRGGBB"; the other brand colours are derived from it by the panel's rules. */
  primaryColor?: string | null;
  /** A font family, as for `setTypeface`; left out, the font stays as it is. */
  typeface?: string | null;
  mode?: ClomniThemeMode | null;
};

export type StartFlowOptions = {
  /** Open the new conversation on screen; otherwise the user learns of it from a push or the unread count. */
  openMessenger?: boolean;
  /** Where in the app, stored with the conversation as `opened_from`. */
  source?: string;
};

/** A push's data as the app's notification library gives it: APNs `userInfo`, FCM `data`. */
export type ClomniPushData = Record<string, unknown>;

/** What each event hands its listener. */
export type ClomniEvents = {
  /** The unread count: at once when the listener is added, then on every change. */
  unreadCountChanged: (count: number) => void;
  /** With the `source` given to `present`. */
  messengerOpened: (source: string | null) => void;
  messengerClosed: () => void;
  /** With the new conversation's id. */
  conversationStarted: (conversationId: string) => void;
  /** A flow reached its end, with the flow's id. */
  flowCompleted: (flowId: string) => void;
};

export type ClomniEventName = keyof ClomniEvents;

export type ClomniSubscription = {
  remove(): void;
};

const NATIVE_EVENT = 'ClomniEvent';

const HEX_COLOR = /^#[0-9A-Fa-f]{6}$/;
const THEME_MODES: readonly string[] = ['light', 'dark', 'system'];

const NOT_LINKED =
  "@clomni/react-native: the native module is not in this app's build. Run `pod install` (iOS) and rebuild the app. " +
  'With Expo, make a development build (npx expo prebuild); Expo Go cannot load it.';

let resolved: Spec | undefined;

/**
 * The native module: the TurboModule in the New Architecture, NativeModules.Clomni in the old one. Looked up on the
 * first call, so importing the package never throws; a build without the module says so then.
 */
function native(): Spec {
  if (resolved) return resolved;
  const module = TurboModuleRegistry.get<Spec>('Clomni') ?? (NativeModules.Clomni as Spec | undefined);
  if (!module) throw new Error(NOT_LINKED);
  resolved = module;
  return module;
}

function warn(message: string): void {
  console.warn(`[Clomni] ${message}`);
}

function isJson(value: unknown, depth = 0): value is JsonValue {
  if (depth > 32) return false;
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return true;
  if (typeof value === 'number') return Number.isFinite(value);
  if (Array.isArray(value)) return value.every((item) => isJson(item, depth + 1));
  if (typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.values(value as object).every((item) => isJson(item, depth + 1));
  }
  return false;
}

/** The native event as the listener of `name` receives it. */
function deliver<Name extends ClomniEventName>(name: Name, event: NativeEvent, listener: ClomniEvents[Name]): void {
  switch (name) {
    case 'unreadCountChanged':
      (listener as ClomniEvents['unreadCountChanged'])(event.count ?? 0);
      break;
    case 'messengerOpened':
      (listener as ClomniEvents['messengerOpened'])(event.text ?? null);
      break;
    case 'messengerClosed':
      (listener as ClomniEvents['messengerClosed'])();
      break;
    default:
      (listener as (value: string) => void)(event.text ?? '');
  }
}

/** Native events of every kind; the New Architecture's EventEmitter, else NativeEventEmitter. */
function subscribe(handler: (event: NativeEvent) => void): ClomniSubscription {
  const module = native();
  if (typeof module.onEvent === 'function') return module.onEvent(handler);
  return new NativeEventEmitter(module as never).addListener(NATIVE_EVENT, (event) => handler(event as NativeEvent));
}

/**
 * The Clomni Messenger (brief 8 · 9): the same calls as the native SDKs, which do the work. Calls may come at any
 * time after the app starts; the messenger opens only when the app asks.
 */
export const Clomni = {
  /** Prepares the connection and push; adds nothing to the app's screens. Call it once, at the app's start. */
  initialize(appId: string, apiKey: string, region = 'eu'): void {
    native().setup(appId, apiKey, region);
  },

  /**
   * The app's logged-in user. `userHash` is hex(HMAC-SHA256(identity_secret, userId)), computed on the app's server;
   * identity_secret never goes into the app.
   */
  loginUser(user: ClomniUser, userHash?: string | null): void {
    native().loginUser({ ...user }, userHash ?? null);
  },

  /** An anonymous visitor, the same one on this device until `logout`. */
  loginUnidentifiedUser(): void {
    native().loginUnidentifiedUser();
  },

  updateUser(update: ClomniUserUpdate): void {
    const { name, language, customAttributes } = update;
    if (customAttributes !== undefined && !isJson(customAttributes)) {
      return console.error('[Clomni] updateUser: customAttributes hold something JSON cannot carry');
    }
    if (name === undefined && language === undefined && customAttributes === undefined) {
      return warn('updateUser: nothing to change');
    }
    native().updateUser(name ?? null, language ?? null, customAttributes ?? null);
  },

  /** Ends the session and deletes the messenger's data on this device; call it when the app's user logs out. */
  logout(): void {
    native().logout();
  },

  setLogLevel(level: ClomniLogLevel): void {
    native().setLogLevel(level);
  },

  /** The app's own font family for the messenger's texts; null is the system font. */
  setTypeface(familyName: string | null): void {
    native().setTypeface(familyName);
  },

  /**
   * The app's own look over the panel's: its colour, font and mode. Each call replaces the last; what is left out
   * stays the panel's. The open messenger and the launcher change at once.
   */
  setTheme(theme: ClomniTheme = {}): void {
    let primaryColor = theme.primaryColor ?? null;
    if (primaryColor !== null && !HEX_COLOR.test(primaryColor)) {
      console.error(`[Clomni] setTheme: primaryColor "${primaryColor}" is not #RRGGBB; the panel's colour stays`);
      primaryColor = null;
    }
    let mode = theme.mode ?? null;
    if (mode !== null && !THEME_MODES.includes(mode)) {
      console.error(`[Clomni] setTheme: mode "${mode}" is not light, dark or system; the panel's mode stays`);
      mode = null;
    }
    native().setTheme(primaryColor, theme.typeface ?? null, mode);
  },

  /** Home. `source` says where in the app (for example "profile_support"). */
  present(source?: string): void {
    native().present(source ?? null);
  },

  /** Straight into a new conversation, with the inbox's first flow. */
  presentNewConversation(source?: string): void {
    native().presentNewConversation(source ?? null);
  },

  presentConversation(conversationId: string): void {
    native().presentConversation(conversationId);
  },

  dismiss(): void {
    native().dismiss();
  },

  /**
   * Starts the flow bound to an app event (for example "ride_problem") in a new conversation; its texts can use
   * `data` as `{{data.ride_id}}`. Nothing happens when no flow is bound to the event.
   */
  startFlow(event: string, data: Record<string, JsonValue> = {}, options: StartFlowOptions = {}): void {
    if (!isJson(data)) return console.error('[Clomni] startFlow: data holds something JSON cannot carry');
    native().startFlow(event, data, options.openMessenger ?? false, options.source ?? null);
  },

  /** The floating button: off by default, and the panel can turn it on too. The app's choice wins. */
  setLauncherVisible(visible: boolean): void {
    native().setLauncherVisible(visible);
  },

  /** Lifts the launcher above the app's tab bar (points on iOS, dp on Android). */
  setBottomPadding(padding: number): void {
    native().setBottomPadding(padding);
  },

  /** The push token: the APNs device token as hex on iOS, the FCM token on Android. */
  setDeviceToken(token: string): void {
    native().setDeviceToken(token);
  },

  /** Whether a push is Clomni's; the app's own pushes are the app's to handle. */
  isClomniPush(data: ClomniPushData | null | undefined): boolean {
    return data != null && typeof data === 'object' && data.clomni === '1';
  },

  /**
   * A Clomni push, as each platform delivers it. iOS: a tap on its notification opens the conversation. Android: the
   * FCM data message as it arrives (onMessage, setBackgroundMessageHandler); the SDK shows it as a notification
   * whose tap opens the conversation. false for the app's own pushes, which stay the app's.
   */
  handlePush(data: ClomniPushData | null | undefined): boolean {
    if (!Clomni.isClomniPush(data)) return false;
    native().handlePush(data as object);
    return true;
  },

  /**
   * iOS: for a push that arrives while the app is open, false for a Clomni push while the messenger is open (it shows
   * the message itself). Android shows or hides its notifications itself: always true there.
   */
  shouldShowForeground(data: ClomniPushData | null | undefined): boolean {
    if (!Clomni.isClomniPush(data)) return true;
    if (Platform.OS !== 'ios') return true;
    return native().shouldShowForeground(data as object);
  },

  /** Android: the small icon of Clomni's notifications, a drawable's name. Nothing on iOS. */
  setNotificationIcon(name: string): void {
    if (Platform.OS !== 'android') return warn('setNotificationIcon is Android only');
    native().setNotificationIcon(name);
  },

  /** Listens to an event until `remove()`. `unreadCountChanged` also hears the current count at once. */
  addEventListener<Name extends ClomniEventName>(name: Name, listener: ClomniEvents[Name]): ClomniSubscription {
    let active = true;
    const subscription = subscribe((event) => {
      if (active && event.name === name) deliver(name, event, listener);
    });
    if (name === 'unreadCountChanged') {
      native()
        .getUnreadCount()
        .then((count) => {
          if (active) deliver(name, { name, count }, listener);
        })
        .catch(() => undefined);
    }
    return {
      remove() {
        if (!active) return;
        active = false;
        subscription.remove();
      },
    };
  },
};

export default Clomni;
