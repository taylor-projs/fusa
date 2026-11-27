#!/usr/bin/env python3
"""Generate audio_sram structural-only exclusions from the current VDB.

The old value-domain exclusions are intentionally gone.  Any raw toggle hole
not proven constant/tied-off below aborts generation and needs TB stimulus.
Run in sim/obj_vcs after urg_report and full_exclusion dumps are generated.
"""
import re

METRICS = ("tgl", "line", "cond", "branch")


def parse_dump(path):
    out = {}
    cur = None
    checksum = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        m = re.match(r"^// CHECKSUM: (.*)$", line)
        if m:
            checksum = m.group(1)
            continue
        m = re.match(r"^// (INSTANCE|MODULE): (.*)$", line)
        if m:
            cur = "%s: %s" % (m.group(1), m.group(2))
            out[cur] = {"checksum": checksum, "rows": []}
            continue
        if cur and line.startswith("// "):
            row = line[3:]
            if row.startswith(("Toggle ", "Block ", "Branch ", "Condition ")):
                out[cur]["rows"].append(row)
    return out


DUMPS = {}
for metric in METRICS:
    DUMPS[metric] = {}
    DUMPS[metric].update(parse_dump("fullexclude." + metric))
    DUMPS[metric].update(parse_dump("fullexclude_module." + metric))


def scope_key(metric, canonical):
    for key in (canonical, canonical + " ", canonical.rstrip()):
        if key in DUMPS[metric]:
            return key
    matches = [key for key in DUMPS[metric] if key.rstrip() == canonical.rstrip()]
    if len(matches) == 1:
        return matches[0]
    raise KeyError("scope not found for %s: %s" % (metric, canonical))


def split_sig(sig):
    m = re.match(r"^([\w.]+)(\[[0-9:]+\])?$", sig)
    if not m:
        return None, None
    return m.group(1), m.group(2) or ""


LAT_BITS = {"[7:0]", "[31:18]"}
FOLLOW = ("u_st_lat", "u_lat_s2", "u_st_flt", "u_flt_s2", "u_st_err", "u_err_s2")


def toggle_family(scope, sig):
    name = scope.split(": ", 1)[1]
    base, bits = split_sig(sig)
    if name in ("audio_sram_top", "audio_sram_regfile", "tb_audio_sram.dut",
                "tb_audio_sram.dut.u_audio_sram_regfile"):
        if sig == "addr[1:0]":
            return "32-bit aligned mbus address"
        if sig in ("rdata[24]", "rdata[26]", "rdata[29]"):
            return "read-mux/ID constant-zero bit"
    if name in ("audio_sram_regfile", "tb_audio_sram.dut.u_audio_sram_regfile"):
        if sig == "par_l_dup_f[1]":
            return "vector != produces a scalar; bit1 is structurally tied off"
        if base in ("st_lat", "st_lat_nxt", "lat_st_s1", "lat_s2") and bits in LAT_BITS:
            return "STA_LAT hardwired reserved bits for AW=10"
        if base in ("en_r", "en_w") and bits == "[31:4]":
            return "CFG_EN upper bits hardwired to zero"
        if base == "inj_r" and sig in ("inj_r[4]", "inj_r[6]", "inj_r[31:15]"):
            return "CFG_INJ reserved bits or fixed key=1010 zero bits"
        if base == "inj_w" and bits == "[31:15]":
            return "CFG_INJ upper bits hardwired to zero"
    if (name.startswith("sync_dff ( parameter WIDTH=32") or name.endswith(".u_lat_sync")):
        if base in ("d", "q") and bits in LAT_BITS:
            return "STA_LAT synchronizer reserved bits for AW=10"
    if name.endswith(FOLLOW):
        if sig == "wr":
            return "follow-image reg_wrap wr tied to 1'b1"
        if name.endswith(("u_st_lat", "u_lat_s2")):
            if base in ("wdata", "rdata", "r.data_q", "rin.data_q") and bits in LAT_BITS:
                return "STA_LAT reg_wrap reserved bits for AW=10"
    if name.endswith(".u_w_en"):
        if base in ("wdata", "rdata", "r.data_q", "rin.data_q") and bits == "[31:4]":
            return "CFG_EN reg_wrap upper bits hardwired to zero"
    if name.endswith(".u_w_inj"):
        if base in ("wdata", "rdata", "r.data_q", "rin.data_q") and bits == "[31:15]":
            return "CFG_INJ reg_wrap upper bits hardwired to zero"
        if base in ("rdata", "r.data_q", "rin.data_q") and sig.endswith(("[4]", "[6]")):
            return "CFG_INJ fixed key=1010 zero bits"
    if name.startswith("reg_wrap ( parameter W=2,RESET=0") and sig == "wr":
        return "all W=2 instances are follow-image wrappers with wr tied high"
    if name.startswith("reg_wrap ( parameter W=32,RESET"):
        if base == "wdata" and bits == "[31:18]":
            return "union of CFG_EN/CFG_INJ/STA_LAT reserved upper bits"
        if base in ("rdata", "r.data_q", "rin.data_q"):
            if bits == "[31:18]":
                return "union of CFG_EN/CFG_INJ/STA_LAT reserved upper bits"
            if bits in ("[4]", "[6]"):
                return "CFG_INJ fixed key=1010 zero bits"
    return None


def raw_toggle_holes(path):
    holes = {}
    scope = None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        m = re.match(r"^Toggle Coverage for (Instance|Module) : (.*)$", line)
        if m:
            name = re.sub(r"\s*\(x\)\s*$", "", m.group(2).strip())
            scope = ("INSTANCE: " if m.group(1) == "Instance" else "MODULE: ") + name
            continue
        m = re.match(r"^\s*(\S+?)\s+(Yes|No)\s+(Yes|No)\s+(Yes|No)"
                     r"(?:\s+(INPUT|OUTPUT|INOUT))?\s*$", line)
        if scope and m and "No" in (m.group(2), m.group(3), m.group(4)):
            sig = m.group(1)
            if toggle_family(scope, sig) is None:
                raise SystemExit("UNCLASSIFIED raw toggle hole: %s :: %s" % (scope, sig))
            actual = scope_key("tgl", scope)
            holes.setdefault(actual, set()).add(sig)
    return holes


def toggle_row(scope, sig):
    base, bits = split_sig(sig)
    declaration = None
    for row in DUMPS["tgl"][scope]["rows"]:
        m = re.match(r'^Toggle (\S+) "(.*)"$', row)
        if m and m.group(1).split("[", 1)[0] == base:
            declaration = m.group(2)
            break
    if declaration is None:
        raise SystemExit("toggle declaration missing: %s :: %s" % (scope, sig))
    return 'Toggle %s%s "%s"' % (base, ((" " + bits) if bits else ""), declaration)


def write_tgl(holes):
    with open("tgl_struct_excl.el", "w", encoding="utf-8") as f:
        f.write("""// audio_sram structural-only toggle exclusions (generated by gen_as_excl.py)
// The SRAM behavioral macro is excluded at VCS cov.cfg scope (non-synthesis model).
// Families:
// 1. addr[1:0]: upstream mbus bridge guarantees 32-bit alignment.
// 2. rdata[24]/[26]/[29]: constant-zero ID/read-mux bits; no register field drives them.
// 3. STA_LAT and its sync/reg_wrap lanes [7:0],[31:18]: reserved zeros for AW=10.
// 4. CFG_EN [31:4] and CFG_INJ [31:15]: hardwired register padding.
// 5. CFG_INJ key bits4/6: accepted writes require key=1010, so these stored bits are 0.
// 6. follow-image reg_wrap wr: u_st_*/u_*_s2 instances tie wr to 1'b1.
// 7. par_l_dup_f[1]: SystemVerilog vector != returns one scalar bit; bit1 is dead.
// No counter, injection-position, duplicate-rail, or other stimulus-reachable
// value-domain item is excluded.  Both real views are generated from raw holes.
""")
        for scope in sorted(holes):
            f.write("\nCHECKSUM: %s\n%s\n" % (DUMPS["tgl"][scope]["checksum"], scope))
            for sig in sorted(holes[scope]):
                f.write(toggle_row(scope, sig) + "\n")


MISC = []


def select(metric, canonical, predicate, description):
    scope = scope_key(metric, canonical)
    rows = [row for row in DUMPS[metric][scope]["rows"] if predicate(row)]
    if len(rows) != 1:
        raise SystemExit("%s: expected one row for %s, got %r" %
                         (description, canonical, rows))
    MISC.append((metric, scope, rows[0], description))


PFX = "INSTANCE: tb_audio_sram.dut.u_audio_sram_regfile."
CONFIG = ("u_w_en", "u_w_inj", "u_c_en", "u_c_inj", "u_w_cmd")
for inst in CONFIG:
    select("line", PFX + inst, lambda row: row.startswith("Block 3 "),
           "parent controls make wr&&selftest impossible")
    select("branch", PFX + inst,
           lambda row: row.startswith("Branch 0 ") and "(0)" in row,
           "parent controls make wr&&selftest impossible")
for inst in FOLLOW:
    for block in (5, 6):
        select("line", PFX + inst, lambda row, b=block: row.startswith("Block %d " % b),
               "follow-image wr=1 makes key-without-wr branch dead")
    for vector in (2, 3):
        select("branch", PFX + inst,
               lambda row, v=vector: row.startswith("Branch 0 ") and ("(%d)" % v) in row,
               "follow-image wr=1 makes wr=0 branches dead")
for module in ("MODULE: reg_wrap ( parameter W=4,RESET=15 )",
               "MODULE: reg_wrap ( parameter W=11,RESET=0 )"):
    select("line", module, lambda row: row.startswith("Block 3 "),
           "all module instances have mutually exclusive wr/selftest")
for block in (5, 6):
    select("line", "MODULE: reg_wrap ( parameter W=2,RESET=0 )",
           lambda row, b=block: row.startswith("Block %d " % b),
           "all W=2 module instances tie wr high")

with open("misc_struct_excl.el", "w", encoding="utf-8") as f:
    f.write("""// audio_sram structural-only line/branch exclusions (gen_as_excl.py)
// Raw COND is 100%; there are no condition exclusions.
// 1. u_w_en/u_w_inj/u_c_en/u_c_inj/u_w_cmd Block3 + wr branch(1,1,-):
//    wr and selftest come from different register offsets, so they cannot coexist.
// 2. follow-image u_st_*/u_*_s2 Block5/6 + wr branches(0,-,1)/(0,-,0):
//    wr is tied high, making selftest-without-wr and the final wr=0 else dead.
// Parameterized MODULE entries are emitted only where the raw module view has
// the same structural hole; covered aggregate branches are not excluded.
""")
    last = None
    for metric, scope, row, description in MISC:
        key = (metric, scope)
        if key != last:
            f.write("\n// %s\nCHECKSUM: %s\n%s\n" %
                    (description, DUMPS[metric][scope]["checksum"], scope))
            last = key
        f.write(row + "\n")

holes = raw_toggle_holes("urg_report/modinfo.txt")
write_tgl(holes)
print("toggle scopes: %d; line/branch exclusion rows: %d" % (len(holes), len(MISC)))
