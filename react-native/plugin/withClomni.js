// @ts-check
// The Expo config plugin of @clomni/react-native (CM-091): what `npx expo prebuild` writes into the native projects so
// the messenger works in a development build. Expo Go cannot load native modules.
//
//   iOS:     NSPhotoLibraryUsageDescription and NSCameraUsageDescription (sending pictures), and for push the
//            aps-environment entitlement and UIBackgroundModes: remote-notification;
//   Android: the POST_NOTIFICATIONS permission (Android 13+) and, given a picture, the small icon of Clomni's
//            notifications as res/drawable/clomni_notification_icon.png (then Clomni.setNotificationIcon);
//   both:    given `microphonePermission`, voice messages: NSMicrophoneUsageDescription and RECORD_AUDIO. Without
//            it the messenger has no microphone (the app declares it, as a native app would).
//
// What the app already has stays: a text, an entitlement or a permission is only added where it is missing, unless an
// option names it. MainActivity is not touched; React Native needs nothing there.
const fs = require('fs');
const path = require('path');

/** The app's own Expo version of the plugin API when it has one (as Expo asks), else this package's. */
function configPlugins() {
  try {
    return require('expo/config-plugins');
  } catch {
    return require('@expo/config-plugins');
  }
}

const {
  AndroidConfig,
  createRunOncePlugin,
  withAndroidManifest,
  withDangerousMod,
  withEntitlementsPlist,
  withInfoPlist,
  withSettingsGradle,
} = configPlugins();

const PACKAGE = require('../package.json');

const DEFAULTS = {
  photoLibraryPermission: 'Allow $(PRODUCT_NAME) to send your photos in support conversations.',
  cameraPermission: 'Allow $(PRODUCT_NAME) to take photos to send in support conversations.',
};

/** The file name the notification icon gets; Clomni.setNotificationIcon('clomni_notification_icon'). */
const NOTIFICATION_ICON = 'clomni_notification_icon';

/**
 * @typedef {object} ClomniPluginOptions
 * @property {string} [photoLibraryPermission] iOS NSPhotoLibraryUsageDescription.
 * @property {string} [cameraPermission] iOS NSCameraUsageDescription.
 * @property {string} [microphonePermission] Voice messages: iOS NSMicrophoneUsageDescription with this text, and
 *   Android's RECORD_AUDIO permission. Off without it.
 * @property {boolean} [push] Push notifications (default true): the entitlement and background mode on iOS, the
 *   notification permission on Android.
 * @property {'development' | 'production'} [apsEnvironment] iOS: the aps-environment to write (default development,
 *   when the app has none; a store build is signed for production anyway).
 * @property {string} [notificationIcon] Android: a white silhouette PNG in the project, for Clomni's notifications.
 * @property {string} [localSdk] A checkout of clomni-mobile-sdk, whose iOS pod
 *   (Podfile) and Android build (settings.gradle) replace the published ones.
 */

/** @param {Record<string, any>} plist @param {ClomniPluginOptions} options */
function setInfoPlist(plist, options) {
  const texts = {
    NSPhotoLibraryUsageDescription: options.photoLibraryPermission,
    NSCameraUsageDescription: options.cameraPermission,
  };
  const defaults = {
    NSPhotoLibraryUsageDescription: DEFAULTS.photoLibraryPermission,
    NSCameraUsageDescription: DEFAULTS.cameraPermission,
  };
  for (const key of Object.keys(texts)) {
    const given = texts[/** @type {keyof typeof texts} */ (key)];
    if (given) plist[key] = given;
    else if (!plist[key]) plist[key] = defaults[/** @type {keyof typeof defaults} */ (key)];
  }
  if (options.microphonePermission) plist.NSMicrophoneUsageDescription = options.microphonePermission;
  if (options.push !== false) {
    const modes = Array.isArray(plist.UIBackgroundModes) ? plist.UIBackgroundModes : [];
    if (!modes.includes('remote-notification')) modes.push('remote-notification');
    plist.UIBackgroundModes = modes;
  }
  return plist;
}

/** @param {Record<string, any>} entitlements @param {ClomniPluginOptions} options */
function setEntitlements(entitlements, options) {
  if (options.push === false) return entitlements;
  if (options.apsEnvironment) entitlements['aps-environment'] = options.apsEnvironment;
  else if (!entitlements['aps-environment']) entitlements['aps-environment'] = 'development';
  return entitlements;
}

/** @param {any} manifest @param {ClomniPluginOptions} options */
function setAndroidManifest(manifest, options) {
  const wanted = [];
  if (options.push !== false) wanted.push('android.permission.POST_NOTIFICATIONS');
  if (options.microphonePermission) wanted.push('android.permission.RECORD_AUDIO');
  if (wanted.length) AndroidConfig.Permissions.ensurePermissions(manifest, wanted);
  return manifest;
}

/** Copies the icon into res/drawable. @param {string} projectRoot @param {string} androidRoot @param {string} icon */
function copyNotificationIcon(projectRoot, androidRoot, icon) {
  const source = path.resolve(projectRoot, icon);
  if (!fs.existsSync(source)) throw new Error(`@clomni/react-native: notificationIcon ${icon} does not exist`);
  if (path.extname(source).toLowerCase() !== '.png') {
    throw new Error('@clomni/react-native: notificationIcon must be a PNG');
  }
  const drawable = path.join(androidRoot, 'app', 'src', 'main', 'res', 'drawable');
  fs.mkdirSync(drawable, { recursive: true });
  fs.copyFileSync(source, path.join(drawable, `${NOTIFICATION_ICON}.png`));
}

/** The Podfile takes the iOS SDK from `sdk`. @param {string} podfile @param {string} sdk */
function usePodFromCheckout(podfile, sdk) {
  const line = `  pod 'ClomniMessenger', :path => '${sdk}'`;
  if (podfile.includes("pod 'ClomniMessenger'")) return podfile;
  const anchor = podfile.match(/^\s*use_expo_modules!.*$/m) || podfile.match(/^\s*use_native_modules!.*$/m);
  if (!anchor || anchor.index === undefined) {
    throw new Error('@clomni/react-native: localSdk: no use_expo_modules! in the Podfile to put the pod after');
  }
  const end = anchor.index + anchor[0].length;
  return `${podfile.slice(0, end)}\n${line}${podfile.slice(end)}`;
}

/** settings.gradle builds ai.clomni:messenger from `sdk`. @param {string} contents @param {string} language @param {string} sdk */
function useAndroidBuildFromCheckout(contents, language, sdk) {
  if (contents.includes('ai.clomni:messenger')) return contents;
  const build = path.join(sdk, 'android');
  const block =
    language === 'kt'
      ? `includeBuild("${build}") {\n    dependencySubstitution {\n        substitute(module("ai.clomni:messenger")).using(project(":messenger"))\n    }\n}\n`
      : `includeBuild('${build}') {\n    dependencySubstitution {\n        substitute(module('ai.clomni:messenger')).using(project(':messenger'))\n    }\n}\n`;
  return `${contents.trimEnd()}\n\n// @clomni/react-native localSdk: the Android SDK from a checkout\n${block}`;
}

/** @type {import('@expo/config-plugins').ConfigPlugin<ClomniPluginOptions | void>} */
const withClomni = (config, options) => {
  const settings = options || {};
  config = withInfoPlist(config, (mod) => {
    mod.modResults = setInfoPlist(mod.modResults, settings);
    return mod;
  });
  config = withEntitlementsPlist(config, (mod) => {
    mod.modResults = setEntitlements(mod.modResults, settings);
    return mod;
  });
  config = withAndroidManifest(config, (mod) => {
    mod.modResults = setAndroidManifest(mod.modResults, settings);
    return mod;
  });
  const icon = settings.notificationIcon;
  if (icon) {
    config = withDangerousMod(config, [
      'android',
      async (mod) => {
        copyNotificationIcon(mod.modRequest.projectRoot, mod.modRequest.platformProjectRoot, icon);
        return mod;
      },
    ]);
  }
  const checkout = settings.localSdk;
  if (checkout) {
    config = withDangerousMod(config, [
      'ios',
      async (mod) => {
        const podfile = path.join(mod.modRequest.platformProjectRoot, 'Podfile');
        const sdk = path.resolve(mod.modRequest.projectRoot, checkout);
        fs.writeFileSync(podfile, usePodFromCheckout(fs.readFileSync(podfile, 'utf8'), sdk));
        return mod;
      },
    ]);
    config = withSettingsGradle(config, (mod) => {
      const sdk = path.resolve(mod.modRequest.projectRoot, checkout);
      mod.modResults.contents = useAndroidBuildFromCheckout(mod.modResults.contents, mod.modResults.language, sdk);
      return mod;
    });
  }
  return config;
};

module.exports = createRunOncePlugin(withClomni, PACKAGE.name, PACKAGE.version);
module.exports.withClomni = withClomni;
module.exports.setInfoPlist = setInfoPlist;
module.exports.setEntitlements = setEntitlements;
module.exports.setAndroidManifest = setAndroidManifest;
module.exports.usePodFromCheckout = usePodFromCheckout;
module.exports.useAndroidBuildFromCheckout = useAndroidBuildFromCheckout;
module.exports.NOTIFICATION_ICON = NOTIFICATION_ICON;
module.exports.DEFAULTS = DEFAULTS;
