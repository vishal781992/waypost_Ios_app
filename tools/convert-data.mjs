// Convert the web repo's ES-module datasets into JSON bundled with the iOS app.
//
// The datasets live in the web repo (../waypoint) as `export const X = ...`. They are
// hand-maintained there, so the iOS app never forks them — it re-generates from source:
//
//   node tools/convert-data.mjs [path-to-web-repo]
//
// Writes Waypost/Resources/{cities,parks,legs,airports,state-parks}.json.
import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const web = resolve(process.argv[2] || resolve(here, '..', '..', 'waypoint'));
const out = resolve(here, '..', 'Waypost', 'Resources');
mkdirSync(out, { recursive: true });

const load = async f => import(pathToFileURL(resolve(web, f)).href);

const M = await load('parks-data.js');
const A = await load('airports.js');
const S = await load('state-parks.js');

const write = (name, value) => {
  const path = resolve(out, name);
  writeFileSync(path, JSON.stringify(value, null, 0) + '\n');
  console.log(`${name.padEnd(18)} ${(JSON.stringify(value).length / 1024).toFixed(0)} KB`);
};

write('cities.json', M.CITIES);
// PARKS is keyed by code in JS; Swift decodes an array and re-keys, so key order can't
// silently reorder the seed shelf.
write('parks.json', Object.values(M.PARKS));
// LEGS keys are "from|to" pairs — kept as an array of {key, ...leg} for the same reason.
write('legs.json', Object.entries(M.LEGS).map(([key, leg]) => ({ key, ...leg })));
write('airports.json', A.AIRPORTS);
write('state-parks.json', S.STATE_PARKS);
