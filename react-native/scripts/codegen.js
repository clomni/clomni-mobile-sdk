#!/usr/bin/env node
// Runs React Native's codegen on src/NativeClomni.ts outside an app: it fails when the spec uses something codegen
// cannot read, and writes the Android and iOS specs an app's build would make (NativeClomniSpec.java,
// ClomniSpec/ClomniSpec.h) to node_modules/.clomni-codegen, where the Android compile check picks the Java one up.
// Apps never run this; their own build runs codegen from package.json's codegenConfig.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const out = path.join(root, 'node_modules', '.clomni-codegen');
const config = require('../package.json').codegenConfig;
const codegen = path.dirname(require.resolve('@react-native/codegen/package.json'));
const specs = path.join(path.dirname(require.resolve('react-native/package.json')), 'scripts', 'generate-specs-cli.js');

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });
const schema = path.join(out, 'schema.json');
const run = (args) => execFileSync(process.execPath, args, { stdio: 'inherit', cwd: root });

run([path.join(codegen, 'lib', 'cli', 'combine', 'combine-js-to-schema-cli.js'), schema,
  path.join(root, config.jsSrcsDir, 'NativeClomni.ts'), '--libraryName', config.name]);
for (const platform of ['android', 'ios']) {
  run([specs, '--platform', platform, '--schemaPath', schema, '--outputDir', path.join(out, platform),
    '--libraryName', config.name, '--javaPackageName', config.android.javaPackageName, '--libraryType', 'modules']);
}
const modules = JSON.parse(fs.readFileSync(schema, 'utf8')).modules;
console.log(`codegen read ${Object.keys(modules).join(', ')}; specs in ${path.relative(root, out)}`);
