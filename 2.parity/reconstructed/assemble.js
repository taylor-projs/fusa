// Assemble autofusadcls.py from transcript parts and verify completeness.
// Usage: node assemble.js
const fs = require('fs');
const path = require('path');

const dir = __dirname;
const tdir = path.join(dir, 'transcripts');
// priority: lower wins on conflict. G (blurry overview) is lowest priority.
const parts = [
  { f: 'partA.txt', prio: 0 }, { f: 'partB.txt', prio: 0 },
  { f: 'partC.txt', prio: 0 }, { f: 'partD.txt', prio: 0 },
  { f: 'partE.txt', prio: 0 }, { f: 'partF.txt', prio: 0 },
  { f: 'partG.txt', prio: 1 },
];

const entries = new Map(); // num -> [{text, src, inferred, prio}]
let parseIssues = [];

for (const p of parts) {
  const fp = path.join(tdir, p.f);
  if (!fs.existsSync(fp)) { parseIssues.push(`MISSING PART FILE: ${p.f}`); continue; }
  const raw = fs.readFileSync(fp, 'utf8').replace(/\r\n/g, '\n');
  let inReport = false;
  for (const line of raw.split('\n')) {
    if (line.startsWith('# REPORT')) { inReport = true; }
    if (inReport) continue;
    if (line.startsWith('### ')) continue;
    const m = line.match(/^(~?)(\d+)\|(.*)$/);
    if (!m) {
      if (line.trim() !== '') parseIssues.push(`${p.f}: unparsed: ${line.slice(0, 80)}`);
      continue;
    }
    const inferred = m[1] === '~';
    const num = parseInt(m[2], 10);
    const text = m[3].replace(/\s+$/, ''); // drop trailing ws
    if (!entries.has(num)) entries.set(num, []);
    entries.get(num).push({ text, src: p.f, inferred, prio: inferred ? p.prio + 2 : p.prio });
  }
}

// resolve conflicts
const conflicts = [];
const final = new Map();
for (const [num, list] of entries) {
  list.sort((a, b) => a.prio - b.prio);
  const best = list[0];
  const distinct = [...new Set(list.map(x => x.text))];
  if (distinct.length > 1) {
    conflicts.push({ num, variants: list.map(x => `[${x.src}${x.inferred ? '~' : ''}] ${x.text}`) });
  }
  final.set(num, best.text);
}

const nums = [...final.keys()].sort((a, b) => a - b);
const min = nums[0], max = nums[nums.length - 1];

// gaps
const gaps = [];
let runStart = null;
for (let i = min; i <= max; i++) {
  if (!final.has(i)) { if (runStart === null) runStart = i; }
  else if (runStart !== null) { gaps.push([runStart, i - 1]); runStart = null; }
}

// write merged file
let out = '';
for (const n of nums) out += final.get(n) + '\n';
fs.writeFileSync(path.join(dir, 'autofusadcls.py'), out);

// ---- structural checks ----
// strip strings & comments (py2 script, no f-strings, no triple-quotes expected)
function stripCode(src) {
  let res = '';
  let i = 0, n = src.length, state = null; // null | "'" | '"' | "'''" | '"""'
  while (i < n) {
    const c = src[i];
    if (state === null) {
      if (src.startsWith("'''", i)) { state = "'''"; i += 3; continue; }
      if (src.startsWith('"""', i)) { state = '"""'; i += 3; continue; }
      if (c === "'") { state = "'"; i++; continue; }
      if (c === '"') { state = '"'; i++; continue; }
      if (c === '#') { while (i < n && src[i] !== '\n') i++; continue; }
      res += c; i++;
    } else if (state === "'" || state === '"') {
      if (c === '\\') { i += 2; continue; }
      if (c === state) { state = null; }
      i++;
    } else { // triple
      if (src.startsWith(state, i)) { state = null; i += 3; } else i++;
    }
  }
  if (state !== null) parseIssues.push(`UNCLOSED STRING STATE ${state} at end of file`);
  return res;
}
const code = stripCode(out);
const pairs = { ')': '(', ']': '[', '}': '{' };
const stack = [];
let line = 1;
let bracketErrors = [];
for (const c of code) {
  if (c === '\n') line++;
  else if (c === '(' || c === '[' || c === '{') bracketStackPush(c, line);
  else if (c === ')' || c === ']' || c === '}') {
    const top = stack.pop();
    if (!top || top.c !== pairs[c]) bracketErrors.push(`line ${line}: unmatched '${c}' (top=${top ? top.c + '@' + top.line : 'empty'})`);
  }
}
function bracketStackPush(c, l) { stack.push({ c, line: l }); }
for (const s of stack) bracketErrors.push(`unclosed '${s.c}' opened at line ${s.line}`);

// structure listing
const defs = [];
out.split('\n').forEach((l, idx) => {
  const m = l.match(/^(\s*)(class\s+\w+|def\s+\w+|if\s+__name__.*)/);
  if (m) defs.push(`${idx + 1}: ${m[1].length > 0 ? ' '.repeat(m[1].length) : ''}${m[2]}`);
});

// tabs check
const tabLines = [];
out.split('\n').forEach((l, idx) => { if (l.includes('\t')) tabLines.push(idx + 1); });

// ---- report ----
console.log(`== ASSEMBLY ==`);
console.log(`lines: ${min}..${max}  total present: ${nums.length}`);
console.log(`\n== GAPS (${gaps.length}) ==`);
for (const g of gaps) console.log(`missing lines ${g[0]}..${g[1]} (${g[1] - g[0] + 1} lines)`);
console.log(`\n== CONFLICTS (${conflicts.length}) ==`);
for (const c of conflicts) { console.log(`line ${c.num}:`); for (const v of c.variants) console.log(`   ${v}`); }
console.log(`\n== PARSE ISSUES (${parseIssues.length}) ==`);
parseIssues.slice(0, 50).forEach(x => console.log(x));
console.log(`\n== BRACKET BALANCE (${bracketErrors.length} errors) ==`);
bracketErrors.slice(0, 30).forEach(x => console.log(x));
console.log(`\n== TAB INDENT LINES (${tabLines.length}) ==`);
console.log(tabLines.slice(0, 20).join(', '));
console.log(`\n== STRUCTURE ==`);
console.log(defs.join('\n'));
