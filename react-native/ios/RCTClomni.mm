// The React Native module "Clomni" on iOS: a TurboModule in the New Architecture (the spec codegen writes from
// src/NativeClomni.ts), an RCTEventEmitter in the old one. ClomniBridge.swift does the work.
#import <Foundation/Foundation.h>

#if __has_include(<ClomniReactNative/ClomniReactNative-Swift.h>)
#import <ClomniReactNative/ClomniReactNative-Swift.h>
#else
#import "ClomniReactNative-Swift.h"
#endif

#ifdef RCT_NEW_ARCH_ENABLED
#import <ClomniSpec/ClomniSpec.h>

@interface RCTClomni : NativeClomniSpecBase <NativeClomniSpec>
@end
#else
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCTClomni : RCTEventEmitter <RCTBridgeModule>
@end
#endif

@implementation RCTClomni {
  ClomniBridge *_clomni;
#ifndef RCT_NEW_ARCH_ENABLED
  BOOL _observing;
#endif
}

RCT_EXPORT_MODULE(Clomni)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (instancetype)init
{
  if (self = [super init]) {
    __weak RCTClomni *weakSelf = self;
    _clomni = [[ClomniBridge alloc] initWithEmit:^(NSDictionary *event) {
      [weakSelf send:event];
    }];
  }
  return self;
}

- (void)send:(NSDictionary *)event
{
#ifdef RCT_NEW_ARCH_ENABLED
  // React Native wires the emitter up after making the module; an event before that has no one to reach.
  if (_eventEmitterCallback) {
    [self emitOnEvent:event];
  }
#else
  if (_observing) {
    [self sendEventWithName:@"ClomniEvent" body:event];
  }
#endif
}

- (void)invalidate
{
  [_clomni invalidate];
#ifndef RCT_NEW_ARCH_ENABLED
  [super invalidate];
#endif
}

#ifndef RCT_NEW_ARCH_ENABLED
- (NSArray<NSString *> *)supportedEvents
{
  return @[ @"ClomniEvent" ];
}

- (void)startObserving
{
  _observing = YES;
}

- (void)stopObserving
{
  _observing = NO;
}
#endif

RCT_EXPORT_METHOD(setup:(NSString *)appId apiKey:(NSString *)apiKey region:(NSString *)region)
{
  [_clomni setupWithAppId:appId apiKey:apiKey region:region];
}

RCT_EXPORT_METHOD(loginUser:(NSDictionary *)user userHash:(nullable NSString *)userHash)
{
  [_clomni loginUser:user userHash:userHash];
}

RCT_EXPORT_METHOD(loginUnidentifiedUser)
{
  [_clomni loginUnidentifiedUser];
}

RCT_EXPORT_METHOD(updateUser:(nullable NSString *)name
                  language:(nullable NSString *)language
                  customAttributes:(nullable NSDictionary *)customAttributes)
{
  [_clomni updateUserWithName:name language:language customAttributes:customAttributes];
}

RCT_EXPORT_METHOD(logout)
{
  [_clomni logout];
}

RCT_EXPORT_METHOD(setLogLevel:(NSString *)level)
{
  [_clomni setLogLevel:level];
}

RCT_EXPORT_METHOD(setTypeface:(nullable NSString *)familyName)
{
  [_clomni setTypeface:familyName];
}

RCT_EXPORT_METHOD(setTheme:(nullable NSString *)primaryColor
                  typeface:(nullable NSString *)typeface
                  mode:(nullable NSString *)mode)
{
  [_clomni setTheme:primaryColor typeface:typeface mode:mode];
}

RCT_EXPORT_METHOD(present:(nullable NSString *)source)
{
  [_clomni presentWithSource:source];
}

RCT_EXPORT_METHOD(presentNewConversation:(nullable NSString *)source)
{
  [_clomni presentNewConversationWithSource:source];
}

RCT_EXPORT_METHOD(presentConversation:(NSString *)conversationId)
{
  [_clomni presentConversation:conversationId];
}

RCT_EXPORT_METHOD(dismiss)
{
  [_clomni dismiss];
}

RCT_EXPORT_METHOD(startFlow:(NSString *)event
                  data:(NSDictionary *)data
                  openMessenger:(BOOL)openMessenger
                  source:(nullable NSString *)source)
{
  [_clomni startFlow:event data:data openMessenger:openMessenger source:source];
}

RCT_EXPORT_METHOD(setLauncherVisible:(BOOL)visible)
{
  [_clomni setLauncherVisible:visible];
}

RCT_EXPORT_METHOD(setBottomPadding:(double)padding)
{
  [_clomni setBottomPadding:padding];
}

RCT_EXPORT_METHOD(setDeviceToken:(NSString *)token)
{
  [_clomni setDeviceToken:token];
}

RCT_EXPORT_METHOD(handlePush:(NSDictionary *)data)
{
  [_clomni handlePush:data];
}

// Android only: nothing to do on iOS (the JS layer does not call it here).
RCT_EXPORT_METHOD(setNotificationIcon:(NSString *)name)
{
}

RCT_EXPORT_METHOD(getUnreadCount:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject)
{
  resolve(@([_clomni unreadCount]));
}

#ifdef RCT_NEW_ARCH_ENABLED
- (NSNumber *)shouldShowForeground:(NSDictionary *)data
{
  return @([_clomni shouldShowForeground:data]);
}

// Events go through the spec's onEvent emitter; NativeEventEmitter's bookkeeping is not needed here.
- (void)addListener:(NSString *)eventName
{
}

- (void)removeListeners:(double)count
{
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeClomniSpecJSI>(params);
}
#else
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(shouldShowForeground:(NSDictionary *)data)
{
  return @([_clomni shouldShowForeground:data]);
}
#endif

@end
