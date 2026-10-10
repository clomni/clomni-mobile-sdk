// The config plugin's mods run on a fake Expo config, as `npx expo prebuild` would run them.
const fs = require('fs');
const os = require('os');
const path = require('path');
const plugin = require('../../app.plugin');
const {
  DEFAULTS,
  NOTIFICATION_ICON,
  setAndroidManifest,
  setEntitlements,
  setInfoPlist,
  useAndroidBuildFromCheckout,
  usePodFromCheckout,
  withClomni,
} = plugin;

const baseConfig = () => ({ name: 'Example', slug: 'example' });

/** Runs one registered mod with `modResults`, the way prebuild hands them over; returns what it made of them. */
async function run(config, platform, name, modResults, projectRoot = '/project') {
  const mod = config.mods[platform][name];
  expect(mod).toBeInstanceOf(Function);
  const result = await mod({
    ...config,
    modResults,
    modRequest: {
      projectRoot,
      platformProjectRoot: path.join(projectRoot, platform),
      platform,
      modName: name,
      introspect: false,
    },
  });
  return result.modResults;
}

const manifest = () => ({ manifest: { $: { 'xmlns:android': 'http://schemas.android.com/apk/res/android' } } });
const permissions = (result) => (result.manifest['uses-permission'] || []).map((p) => p.$['android:name']);

describe('Info.plist', () => {
  it('adds the photo and camera texts and the push background mode where the app has none', () => {
    expect(setInfoPlist({}, {})).toEqual({
      NSPhotoLibraryUsageDescription: DEFAULTS.photoLibraryPermission,
      NSCameraUsageDescription: DEFAULTS.cameraPermission,
      UIBackgroundModes: ['remote-notification'],
    });
  });

  it("keeps the app's own texts and modes, unless an option names them", () => {
    const app = {
      NSCameraUsageDescription: 'Kamera üçün',
      UIBackgroundModes: ['fetch', 'remote-notification', 'audio'],
    };
    expect(setInfoPlist({ ...app, UIBackgroundModes: [...app.UIBackgroundModes] }, {})).toEqual({
      NSCameraUsageDescription: 'Kamera üçün',
      NSPhotoLibraryUsageDescription: DEFAULTS.photoLibraryPermission,
      UIBackgroundModes: ['fetch', 'remote-notification', 'audio'],
    });
    const named = setInfoPlist({ ...app, UIBackgroundModes: ['fetch'] },
      { photoLibraryPermission: 'Şəkillər', cameraPermission: 'Kamera' });
    expect(named.NSPhotoLibraryUsageDescription).toBe('Şəkillər');
    expect(named.NSCameraUsageDescription).toBe('Kamera');
    expect(named.UIBackgroundModes).toEqual(['fetch', 'remote-notification']);
  });

  it('leaves the background modes alone without push', () => {
    expect(setInfoPlist({}, { push: false }).UIBackgroundModes).toBeUndefined();
  });

  it('adds the microphone text for voice messages only when the app asks for them', () => {
    expect(setInfoPlist({}, {}).NSMicrophoneUsageDescription).toBeUndefined();
    expect(setInfoPlist({}, { microphonePermission: 'Səsli mesaj üçün' }).NSMicrophoneUsageDescription).toBe('Səsli mesaj üçün');
  });
});

describe('entitlements', () => {
  it('writes aps-environment where the app has none, keeps the one it has, and takes the option', () => {
    expect(setEntitlements({}, {})).toEqual({ 'aps-environment': 'development' });
    expect(setEntitlements({ 'aps-environment': 'production' }, {})).toEqual({ 'aps-environment': 'production' });
    expect(setEntitlements({ 'aps-environment': 'development' }, { apsEnvironment: 'production' }))
      .toEqual({ 'aps-environment': 'production' });
    expect(setEntitlements({}, { push: false })).toEqual({});
  });
});

describe('Android manifest', () => {
  it('asks for RECORD_AUDIO only for voice messages, with or without push', () => {
    expect(permissions(setAndroidManifest(manifest(), { microphonePermission: 'Səs' })))
      .toEqual(['android.permission.POST_NOTIFICATIONS', 'android.permission.RECORD_AUDIO']);
    expect(permissions(setAndroidManifest(manifest(), { push: false, microphonePermission: 'Səs' })))
      .toEqual(['android.permission.RECORD_AUDIO']);
    expect(permissions(setAndroidManifest(manifest(), { push: false }))).toEqual([]);
  });

  it('asks for POST_NOTIFICATIONS once', () => {
    const once = setAndroidManifest(manifest(), {});
    expect(permissions(once)).toEqual(['android.permission.POST_NOTIFICATIONS']);
    expect(permissions(setAndroidManifest(once, {}))).toEqual(['android.permission.POST_NOTIFICATIONS']);
    expect(permissions(setAndroidManifest(manifest(), { push: false }))).toEqual([]);
  });
});

describe('localSdk, a checkout in place of the published SDKs', () => {
  const podfile = "target 'Example' do\n  use_expo_modules!\n  config = use_native_modules!\nend\n";

  it('puts the iOS SDK pod after use_expo_modules!, once', () => {
    const once = usePodFromCheckout(podfile, '/src/clomni-mobile-sdk');
    expect(once).toBe("target 'Example' do\n  use_expo_modules!\n  pod 'ClomniMessenger', :path => '/src/clomni-mobile-sdk'\n" +
      '  config = use_native_modules!\nend\n');
    expect(usePodFromCheckout(once, '/src/clomni-mobile-sdk')).toBe(once);
    expect(() => usePodFromCheckout("target 'Example' do\nend\n", '/x')).toThrow('no use_expo_modules!');
  });

  it('builds ai.clomni:messenger from the checkout, in Groovy or Kotlin', () => {
    const groovy = useAndroidBuildFromCheckout("rootProject.name = 'Example'\n", 'groovy', '/src/sdk');
    expect(groovy).toContain("includeBuild('/src/sdk/android') {");
    expect(groovy).toContain("substitute(module('ai.clomni:messenger')).using(project(':messenger'))");
    expect(useAndroidBuildFromCheckout(groovy, 'groovy', '/src/sdk')).toBe(groovy);
    const kotlin = useAndroidBuildFromCheckout('rootProject.name = "Example"', 'kt', '/src/sdk');
    expect(kotlin).toContain('includeBuild("/src/sdk/android") {');
  });

  it('runs in a prebuild', async () => {
    const project = fs.mkdtempSync(path.join(os.tmpdir(), 'clomni-plugin-'));
    try {
      fs.mkdirSync(path.join(project, 'ios'));
      fs.writeFileSync(path.join(project, 'ios', 'Podfile'), podfile);
      const config = withClomni(baseConfig(), { localSdk: '../clomni-mobile-sdk' });
      await run(config, 'ios', 'dangerous', {}, project);
      expect(fs.readFileSync(path.join(project, 'ios', 'Podfile'), 'utf8'))
        .toContain(`pod 'ClomniMessenger', :path => '${path.resolve(project, '../clomni-mobile-sdk')}'`);
      const settings = await run(config, 'android', 'settingsGradle', { contents: '', language: 'groovy' }, project);
      expect(settings.contents).toContain(`includeBuild('${path.resolve(project, '../clomni-mobile-sdk')}/android')`);
    } finally {
      fs.rmSync(project, { recursive: true, force: true });
    }
  });
});

describe('the plugin in a prebuild', () => {
  it('registers its mods once, and they do the above', async () => {
    const config = plugin(plugin(baseConfig()));
    expect(config._internal.pluginHistory['@clomni/react-native']).toBeDefined();
    expect(Object.keys(config.mods.ios).sort()).toEqual(['entitlements', 'infoPlist']);
    expect(Object.keys(config.mods.android)).toEqual(['manifest']);

    const plist = await run(config, 'ios', 'infoPlist', { CFBundleName: 'Example' });
    expect(plist.NSCameraUsageDescription).toBe(DEFAULTS.cameraPermission);
    expect(plist.UIBackgroundModes).toEqual(['remote-notification']);
    expect(await run(config, 'ios', 'entitlements', {})).toEqual({ 'aps-environment': 'development' });
    expect(permissions(await run(config, 'android', 'manifest', manifest())))
      .toEqual(['android.permission.POST_NOTIFICATIONS']);
  });

  it('takes options as app.json gives them', async () => {
    const config = withClomni(baseConfig(), { cameraPermission: 'Kamera', apsEnvironment: 'production', push: true });
    expect((await run(config, 'ios', 'infoPlist', {})).NSCameraUsageDescription).toBe('Kamera');
    expect(await run(config, 'ios', 'entitlements', { 'aps-environment': 'development' }))
      .toEqual({ 'aps-environment': 'production' });
  });

  it('puts the notification icon into res/drawable for Clomni.setNotificationIcon', async () => {
    const project = fs.mkdtempSync(path.join(os.tmpdir(), 'clomni-plugin-'));
    try {
      fs.mkdirSync(path.join(project, 'assets'));
      fs.writeFileSync(path.join(project, 'assets', 'notification.png'), Buffer.from([0x89, 0x50, 0x4e, 0x47]));
      fs.writeFileSync(path.join(project, 'assets', 'notification.jpg'), 'not a png');
      const config = withClomni(baseConfig(), { notificationIcon: './assets/notification.png' });
      expect(Object.keys(config.mods.android).sort()).toEqual(['dangerous', 'manifest']);
      await run(config, 'android', 'dangerous', {}, project);
      const copied = path.join(project, 'android', 'app', 'src', 'main', 'res', 'drawable', `${NOTIFICATION_ICON}.png`);
      expect(fs.readFileSync(copied)).toEqual(Buffer.from([0x89, 0x50, 0x4e, 0x47]));

      const jpg = withClomni(baseConfig(), { notificationIcon: './assets/notification.jpg' });
      await expect(run(jpg, 'android', 'dangerous', {}, project)).rejects.toThrow('must be a PNG');
      const missing = withClomni(baseConfig(), { notificationIcon: './assets/none.png' });
      await expect(run(missing, 'android', 'dangerous', {}, project)).rejects.toThrow('does not exist');
    } finally {
      fs.rmSync(project, { recursive: true, force: true });
    }
  });
});
