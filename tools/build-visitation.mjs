// Build the bundled monthly-visitation profile for every national park.
//
//   node tools/build-visitation.mjs [--limit N] [--park CODE]
//
// Writes Waypost/Resources/visitation.json.
//
// Why bundled and not fetched: the park service publishes real monthly visitor counts,
// 1979 to date, but only through an SSRS report viewer — there is no JSON API for it. The
// numbers also barely move; a park's shape of the year is the same in March as it was in
// January. So this runs at build time and the app ships the answer, which keeps the park
// screen working with no signal and costs no request at runtime.
//
// Three hops per park, because the report viewer will not hand over the data directly:
//   1. the report page, which is an iframe wrapper
//   2. the iframe, which carries a ReportSession and a ControlID
//   3. the export handler, with Format=CSV
//
// The third hop is the one worth knowing about. Scraping the rendered HTML works — the
// numbers are in there — but it is 272 KB of nested SSRS markup per park. The same handler
// that draws the "export" menu takes Format=CSV and returns 6 KB of exactly the table.
// (`rs:Format=CSV` on the report URL itself is refused; that is a different parameter.)
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPORT = 'Recreation Visitors By Month (1979 - Last Calendar Year)';
const BASE = 'https://irma.nps.gov/Stats';
// ASCII only: HTTP headers are ByteStrings, and an em dash here throws before the request.
const UA = 'ParkHop build script - bundling published NPS visitation counts';

/// How many complete calendar years to average. Enough to smooth a fire year or a flood
/// closure without reaching back to a park that has since changed how it counts.
const YEARS = 3;

/// Where the visitation system's code for a park is not the one the NPS API uses.
///
/// Sequoia and Kings Canyon are administered jointly and share `seki` in the API, but the
/// stats system counts them separately and answers "Report Viewer Configuration Error" to
/// the joint code. They are two entries in the app and two curves here.
const STATS_CODE = {
  'np-sequoia': 'SEQU',
  'np-kings-canyon': 'KICA',
};

const args = process.argv.slice(2);
const argOf = (name) => {
  const i = args.indexOf(name);
  return i === -1 ? null : args[i + 1];
};

const parks = JSON.parse(readFileSync(resolve(root, 'Waypost/Resources/national-parks.json'), 'utf8'));
const only = argOf('--park');
const limit = Number(argOf('--limit') ?? 0);
let queue = parks.filter((p) => p.npsCode);
if (only) queue = queue.filter((p) => p.npsCode.toLowerCase() === only.toLowerCase());
if (limit > 0) queue = queue.slice(0, limit);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function attempt(work, tries) {
  let last;
  for (let n = 1; n <= tries; n++) {
    try {
      return await work();
    } catch (error) {
      last = error;
      if (n < tries) await sleep(1500 * n);
    }
  }
  throw last;
}

async function get(url, cookie) {
  const headers = { 'User-Agent': UA };
  if (cookie) headers.Cookie = cookie;
  const res = await fetch(url, { headers, redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const set = res.headers.getSetCookie?.() ?? [];
  return { body: await res.text(), cookie: set.map((c) => c.split(';')[0]).join('; ') || cookie };
}

/// The twelve monthly counts for one park, averaged over the last complete years.
async function visitation(npsCode) {
  const code = npsCode.toUpperCase();

  const wrapper = await get(`${BASE}/SSRSReports/Park Specific Reports/${REPORT}?Park=${code}`);
  const src = wrapper.body.match(/<iframe[^>]+src="([^"]+)"/i)?.[1];
  if (!src) throw new Error('no report iframe');
  const inner = await get(BASE.replace('/Stats', '') + decodeEntities(src), wrapper.cookie);

  const session = inner.body.match(/ReportSession=([0-9a-z]+)/i)?.[1];
  const control = inner.body.match(/ControlID=([0-9a-f]+)/i)?.[1];
  if (!session || !control) throw new Error('no report session');

  const csvUrl =
    `${BASE}/Reserved.ReportViewerWebControl.axd?ReportSession=${session}` +
    `&ControlID=${control}&Culture=1033&CultureOverrides=True&UICulture=1033` +
    `&UICultureOverrides=True&ReportStack=1&OpType=Export&FileName=visits` +
    `&ContentDisposition=OnlyHtmlInline&Format=CSV`;
  const csv = await get(csvUrl, inner.cookie);
  return parse(csv.body);
}

function decodeEntities(s) {
  return s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}

/// Rows look like: 2024,"110,891","105,737",…,"4,154,349"
/// The trailing column is the annual total, and the current year is partial — a month with
/// no number yet is an empty cell, which is how an incomplete year is spotted and skipped.
function parse(csv) {
  const rows = csv.split(/\r?\n/);
  const years = [];
  for (const row of rows) {
    const cells = row.match(/("[^"]*"|[^,]*)/g)?.filter((_, i) => i % 2 === 0) ?? [];
    const year = Number(cells[0]);
    if (!Number.isInteger(year) || year < 1979 || year > 2999) continue;
    const months = cells.slice(1, 13).map((c) => {
      const n = Number(c.replace(/["\s,]/g, ''));
      return Number.isFinite(n) && c.replace(/["\s]/g, '') !== '' ? n : null;
    });
    if (months.length !== 12 || months.some((m) => m === null)) continue; // partial year
    years.push({ year, months });
  }
  if (!years.length) throw new Error('no complete years');

  years.sort((a, b) => b.year - a.year);
  const used = years.slice(0, YEARS);
  const monthly = Array.from({ length: 12 }, (_, m) =>
    Math.round(used.reduce((sum, y) => sum + y.months[m], 0) / used.length)
  );
  return { monthly, years: used.map((y) => y.year).sort() };
}

/// How many parks answer to each NPS code, so an alias is only written where it is
/// unambiguous.
const npsCodeCount = {};
for (const p of parks) {
  if (p.npsCode) npsCodeCount[p.npsCode] = (npsCodeCount[p.npsCode] ?? 0) + 1;
}

const out = {};
const failed = [];
for (const [i, park] of queue.entries()) {
  const stats = STATS_CODE[park.code] ?? park.npsCode;
  process.stdout.write(`[${i + 1}/${queue.length}] ${stats.toLowerCase()} ${park.name} … `);
  try {
    // The report viewer fails a few requests a run — an HTTP 500, or a page that comes
    // back without a session — and it is a different few every time, so they are worth
    // asking again rather than shipping a park with no curve.
    const { monthly, years } = await attempt(() => visitation(stats), 3);
    // Written under both codes the app knows a park by. The bundled catalogue calls Grand
    // Canyon `np-grand-canyon`; the eight curated parks call it `grca`, and the same park
    // arrives at the lookup under either depending on which list it came from. Keying on
    // one of them left the eight best-known parks in the app with no curve at all.
    //
    // The NPS alias is skipped where two parks share it — Sequoia and Kings Canyon both
    // answer to `seki`, and one would quietly overwrite the other's numbers.
    out[park.code] = { monthly, years };
    if (npsCodeCount[park.npsCode] === 1 && park.npsCode !== park.code) {
      out[park.npsCode] = { monthly, years };
    }
    const peak = monthly.indexOf(Math.max(...monthly));
    const low = monthly.indexOf(Math.min(...monthly));
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    console.log(`peak ${names[peak]}, quietest ${names[low]} (${years.join('–')})`);
  } catch (error) {
    failed.push(`${park.code}: ${error.message}`);
    console.log(`FAILED — ${error.message}`);
  }
  await sleep(400); // the report viewer is a shared government service; do not hammer it
}

if (!only && !limit) {
  writeFileSync(
    resolve(root, 'Waypost/Resources/visitation.json'),
    JSON.stringify(out, null, 0) + '\n'
  );
  console.log(`\nWrote visitation.json — ${Object.keys(out).length} parks.`);
}
if (failed.length) {
  console.log(`\n${failed.length} did not resolve:`);
  for (const f of failed) console.log('  ' + f);
}
