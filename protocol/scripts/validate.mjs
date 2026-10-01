// Validates every example and fixture against the protocol schemas (JSON Schema draft 2020-12).
// Each folder with an index.json lists its files and the schema each must pass; a fixture may instead declare
// "valid": false, and then it must fail. A .json file the index does not list fails too, since it would
// otherwise never be checked. Exit code 1 on any mismatch, so CI can run it as is.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const schemaDir = join(root, 'schema');

const ajv = new Ajv2020({ strict: true, allErrors: true, strictRequired: false });
addFormats(ajv);
for (const name of readdirSync(schemaDir).filter(file => file.endsWith('.json'))) {
  ajv.addSchema(JSON.parse(readFileSync(join(schemaDir, name), 'utf8')), name);
}

const base = 'https://app.clomni.ai/protocol/v1/';
const validatorFor = ref => {
  const [file, pointer] = ref.split('#');
  const validate = ajv.getSchema(pointer ? `${base}${file}#${pointer}` : `${base}${file}`);
  if (!validate) throw new Error(`no schema ${ref}`);
  return validate;
};

const folders = ['examples/brief', 'fixtures'].map(folder => join(root, folder)).filter(folder => existsSync(join(folder, 'index.json')));
let failures = 0;
let checked = 0;
for (const folder of folders) {
  const index = JSON.parse(readFileSync(join(folder, 'index.json'), 'utf8'));
  const listed = new Set(index.map(entry => entry.file));
  for (const file of readdirSync(folder).filter(name => name.endsWith('.json') && name !== 'index.json' && !listed.has(name))) {
    checked += 1;
    failures += 1;
    console.error(`✗ ${folder.slice(root.length + 1)}/${file}: not listed in index.json`);
  }
  for (const entry of index) {
    const data = JSON.parse(readFileSync(join(folder, entry.file), 'utf8'));
    const validate = validatorFor(entry.schema);
    const ok = validate(data);
    const expected = entry.valid !== false;
    checked += 1;
    if (ok !== expected) {
      failures += 1;
      console.error(`✗ ${folder.slice(root.length + 1)}/${entry.file} (${entry.schema}): expected ${expected ? 'valid' : 'invalid'}`);
      if (validate.errors) console.error(JSON.stringify(validate.errors, null, 2));
    }
  }
}
console.log(`${checked - failures}/${checked} files match their schema`);
process.exit(failures ? 1 : 0);
