// The native module as React Native's codegen reads it (New Architecture: a TurboModule; the old architecture finds
// the same methods on NativeModules.Clomni). Apps use src/index.ts, not this file.
import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { EventEmitter, Int32 } from 'react-native/Libraries/Types/CodegenTypes';

/** One event of the SDK: `name` says which; `count` and `text` carry its value. */
export type NativeEvent = {
  name: string;
  count?: Int32;
  text?: string;
};

export interface Spec extends TurboModule {
  // `initialize` in JS; another name here, since native modules already have an initialize() of their own.
  setup(appId: string, apiKey: string, region: string): void;
  loginUser(user: Object, userHash: string | null): void;
  loginUnidentifiedUser(): void;
  updateUser(name: string | null, language: string | null, customAttributes: Object | null): void;
  logout(): void;
  setLogLevel(level: string): void;
  setTypeface(familyName: string | null): void;

  present(source: string | null): void;
  presentNewConversation(source: string | null): void;
  presentConversation(conversationId: string): void;
  dismiss(): void;
  startFlow(event: string, data: Object, openMessenger: boolean, source: string | null): void;
  setLauncherVisible(visible: boolean): void;
  setBottomPadding(padding: number): void;

  setDeviceToken(token: string): void;
  handlePush(data: Object): void;
  // iOS only.
  shouldShowForeground(data: Object): boolean;
  // Android only.
  setNotificationIcon(name: string): void;

  getUnreadCount(): Promise<number>;

  // New Architecture (React Native 0.76+): events through codegen's EventEmitter.
  readonly onEvent: EventEmitter<NativeEvent>;
  // Old architecture: NativeEventEmitter, event "ClomniEvent".
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Clomni');
