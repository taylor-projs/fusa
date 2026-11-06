# SPEC — reg_gen_py RDL subset & generation rules

Authoritative schema for the RDL that `rdl2reg.py` accepts and the Verilog it
emits.  Semantics are a faithful port of `reg_gen_parity.pl` v0p3-2023/4/5 —
where this doc and the perl disagree, the perl wins and this doc is wrong.

## 1. Excel input schema (excel2rdl.py)

Worksheet #1.  Header area (rows before the column-header row); two layouts
accepted — the perl-canonical single-cell form (what the Horizon template
uses, required for perl interop) and a two-column KEY/value form:

| entry (single-cell form) | meaning | default |
| --- | --- | --- |
| `BASE_ADDR:0x0` | macro-footer base | 0x0 |
| `ADDR_WIDTH=13` | APB address width | 13 |
| `APB3` | bus type (**only APB3 supported**) | APB3 |
| `REG_NUM=1` | informational | 0 |
| `ECC_OFFSET:0x04` | ECC region lower bound (**required**) — start of the standard block | — |

Column header row: first cell `Offset`; required columns
`Offset | Register Name | SubBits | Field Name | Attribute | DefaultValue`
(`Description`, `Shadow/ShadowAddr/CDC/SetClear` accepted but unsupported).

**Perl interop quirk**: the row directly after the column header is
**skipped unconditionally** by reg_gen_parity.pl (the `registers group`
separator in the Horizon template) — keep such a row in any xlsx meant for
the perl flow.  Non-offset rows are otherwise ignored by excel2rdl.

Register rows: a non-empty `Register Name` starts a register at `Offset`
(`[0-9a-fA-F]+h`); each field row carries `SubBits` `[msb]` or `[msb:lsb]`,
`Attribute` (§3 token), `DefaultValue` (`<width>'<radix><digits>`, required
for non-reserved fields).  Fields listed msb→lsb.  Repeated `reserved` rows
are renamed `reserved_1, reserved_2 ...` (RDL forbids duplicate instance
names); the model normalizes `reserved[_n]` back to `reserved`.

Accepted shorthands:

- **`W1C/R`** is an alias for `W1C` (readable W1C status; canonicalized at
  load so the RDL/ATTR macros stay C-legal).
- **bare `0`** DefaultValue (reserved rows and plain zero cells) is
  normalized to `<width>'h0` at load.  The perl's Reg_value loop-2 instead
  reuses a stale radix/digits pair from the previous field on such cells
  (e.g. PASSWORD's `0badbeef` leaking into the next register's DFLT
  macro) — never reproduced; see §11.
- every register's fields must **exactly cover 32 bits** — the error names
  the missing/overlapping ranges (hand-drawn sketches often leave a gap
  implicit, e.g. `[3:2]` between `[n-1:4]` and `[1]`).

### 1.1 Standard FuSa block auto-append

When the map contains **no register at/above `ECC_OFFSET`** (in particular
no `PASSWORD`), excel2rdl appends the standard block
([fusa_std_block.md](fusa_std_block.md) v1.0) at `ECC_OFFSET` and the xlsx
should contain only functional registers:

- functional registers must all sit **below ECC_OFFSET** (a functional
  register inside the ECC region marks a hand-written map — nothing is
  appended, no error);
- ext faults come from the optional `ExtInt` worksheet:
  `Field Name | Bits | Description`, one row per fault, **first row =
  highest bit** (allocated bottom-up from bit1; bit0 is always
  `parity_err`; total ≤ 31 bits);
- `ExtInt` + a hand-written map in the same file is an error;
- `--no-std-block` disables the append (full hand-written map);
- `xlsx_materialize.py` writes the appended block back out as plain rows
  (canonical header + `registers group` separator + literal `reserved`
  names) so the patched perl produces byte-identical output.

### 1.2 v2 FuSa block `n`/`m` placeholders (hand-written map)

The v2 3-register FuSa block sketch may be written with placeholders; they
are resolved from the map itself at load:

| cell (verbatim) | resolves to |
| --- | --- |
| `reserved` `[31:n]` | `[31:m+4]` |
| `reg<m-1>~reg0_par_err_sta` `[n-1:4]` | `reg_par_err_sta [m+3:4]` |
| `par_selftest_reg_sel` `[n-1:4]` | `[m+3:4]` |
| `<m>''b0` (DefaultValue) | `<m>'b0` |

`m` = the parity-bank size (non-RO/RES regs that are not PASSWORD/Set*/
Status*, i.e. every register the bank actually protects), `n = m+4`;
error if `n > 31` (max `m = 27`).  Example (v2 demo map,
tests_edge `TestV2FuSa`): 5 bank regs → `m=5`, `n=9` →
`reserved[31:9]`, `reg_par_err_sta[8:4]`.  Bits `[3:2]` of
STA_PAR/CFG_REGST are **reserved rows you must write** (the sketch leaves
them implicit; the 32-bit cover check rejects the gap by name).

## 2. RDL subset grammar (rdl2reg.py)

```ebnf
file      := { property_decl } addrmap ;
property_decl := "property" ID "{" "type" "=" ("string"|"longint") ";"
                              "component" "=" ("addrmap"|"field") ";" "}" ";"
addrmap   := "addrmap" ID "{" addrmap_prop* "default" "regwidth" "=" "32" ";"
                             { reg_decl } "}" ID ";"
addrmap_prop := ("apb_addr_width" | "base_addr" | "ecc_offset") "=" NUM ";"
              | "bus_type" "=" STR ";"
reg_decl  := "reg" "{" { field_decl } "}" ID "@" NUM ";"
field_decl:= "field" "{" (ID "=" value ";")* "}" ID "[" NUM [":" NUM] "]" ";"
value     := STR | NUM | ID
```

Comments `//...` and `/*...*/` are stripped (`/*autoarg*/` markers are
re-inserted by post_autos).  Field properties:

| prop | required | notes |
| --- | --- | --- |
| `attr` | **yes** | original Excel token (§3); **authoritative** for codegen |
| `reset` | **yes** | verbatim token re-emitted into reg_default_value |
| `sw`/`onwrite`/`onread` | no | interop cross-check vs `attr` (§3 table); mismatch = error |
| `hw` | no | not checked |
| `desc` | no | `\"` `\\` `\n` escaping, round-trips |
| anything else | — | error (`cdc/shadow/setclear` unsupported) |

## 3. Attribute tokens and semantics

Token → flag: `W1S/W1F→w1s`, `W1C→w1c`, `W0S→w0s`, `W0F/W0C→w0c`, `WT→wt`,
`RC→rc`, `RW/MRW/WO/MWO→rw`, `HW→hw`, `RO→ro`, `RES→(reserved rows)`.

Interoperable sw mapping (checked when present; `attr` wins):
RW/MRW=`rw`, WO/MWO=`w`, RO/RES=`r`, RC=`r`+`onread=rclr`, WT=`rw`,
W1S/W1F=`rw`+`woset`, W1C=`rw`+`woclr`, W0S=`rw`+`wzs`, W0C/W0F=`rw`+`wzc`.

A register's `reg_attr` is the single flag if exactly one is set, else `MIX`
(all-RES = `RES`).  `RO`/`RES` registers are excluded from the parity bank
and from `reg_num_w`.

## 4. Name magic (CASE-SENSITIVE, load-bearing)

| pattern | role |
| --- | --- |
| `PASSWORD` (exact) | key register; **always excluded from the bank**; the only ECC-region write NOT passwd-gated |
| `^FUSA_CTRL` | config register; 0x04-0x14 writes gated by passwd |
| `Mask\d*$` | mask register; bank member; passwd-gated |
| `Set\d*$` | set register; **excluded from bank**; passwd-gated |
| `Status\d*$` | status register; **excluded from bank**; its `<x>_status` fields (≠ `parity_err_status`) declare **ext ints** |

Passwd gating: every APB write in the ECC region except PASSWORD itself is
`&& (passwd==32'h95f2d303)`-gated (`hwr_*` assigns).  Excel names are
mixed-case (`MIssionIntStatusSet0`) — all-caps names are silently NOT
recognized; both tools share these exact rules (regmodel.py).

**No-PASSWORD maps** (v2 style): the perl would reference an undeclared
`passwd` (compile error); reg_gen_py omits the gating entirely — ECC
registers are directly writable.  Two more v2-safe determinism rules:
`parity_decoder_bypass` ties to `1'b0` when the map carries no
`parity_decoder_enable` field (perl leaves an X wire — decoder permanently
bypassed), and absent legacy FUSA_CTRL control fields
(`fault_injection_en` / `parity_fault_injection` / `parity_invert` /
`parity_err_status` / `parity_err_mask`) are tied to safe constants
(`0`/`4'h0`) instead of floating.

ECC region: `offset >= ecc_offset`.  **ECC_OFFSET is the lower bound of the
FUSA interrupt region** — placing it above the status registers silently
drops those interrupts from the generated logic.

## 5. Ext ints

Every ecc `<name>_status` field requires `<name>_mask` and `<name>_set`
fields somewhere in the map (error otherwise; duplicates error).  Width 1:
`reg <name>_status;` + single always block + `output <name>;` +
`input <name>_status_wr/_in;`.  Width >1: `reg [w-1:0] <name>_status;` +
generate loop (`genvar i_<name>_status`) + `output [w-1:0] <name>;` +
looped `_wr/_in` inputs.

## 6. Bank accounting

The perl computes `func_num_w = reg_num_w − ecc_num_w + fusa_ctrl_mask`
(`reg_num_w` = non-RO/RES regs, `ecc_num_w` = ecc ones, `fusa_ctrl_mask` =
ecc `FUSA_CTRL`/`Mask` regs) — an approximation that implicitly assumes
every ecc reg other than FUSA_CTRL/Mask is bank-skipped Set*/Status*.  It
**over**-provisions when the std block sits outside the ECC region (the
oversized bank arrays are part of the legacy byte-exact output) and
**under**-provisions on v2 maps (bank-member ecc regs like STA_PAR).
reg_gen_py takes `func_num_w = max(perl formula, actual bank size)`:
byte-identical wherever the perl was right, always big enough to index
every member.  `reg_default_value`/`reg_data_*` are indexed by bank order
(non-RO/RES, PASSWORD/Set/Status skipped, `num -= 1`).

## 7. reg_data group emission (per register, 10 groups)

Groups: `res w1s w1c w0s w0c wt rc wr hw` (+ `hw_wdata`).

- A group with no contributing field stays the shortcut `32'h0;`.
- Terms are **prefixed**, never replaced:
  - flag terms (w1 and w>1): comma-prefixed — `,hwr_X` / `,{w{hwr_X}}`.
    The perl writes the **w1 term bare** (`s/};/hwr_X};/`), fusing it onto
    the previous term (`{16'h0hwr_FUNC0,15'h0}`) — invalid Verilog the
    moment a w1 W1S/W1C/W0S/W0C/WT/RC field sits in a bank-member
    register.  Legacy maps never trip it (those attrs live only in
    bank-skipped Set*/Status* regs; regression stays byte-identical);
    v2 STA_PAR does — FIXED here;
  - w32: wholesale `{32{hwr_X}};` replaces the accumulator (also latent
    perl behavior — it discards earlier terms; not triggered by any
    supported map shape);
  - tmp terms (`wr/mwr/hw/hwd/hw_sync`): `,\n` + 36 spaces;
  - zero terms: `,w'h0` single-line;
  - RC hw/hwdata terms: `,field` (perl wrote the bare name — same fix as
    the w1 flag terms).
- reserved fields: `,{w{1'b1}}` into **res only** (`,1'b1` when w1); the
  other nine groups get `,w'h0`.
- per-group cleanup strips leading `{,` → `{`.

`reg_default_value` loop-1 terms always carry commas; loop-2 splits the
reset token verbatim (radix preserved — `4'b0` stays binary).

## 8. Structural rules (validated, error otherwise)

- bus must be APB3; every reg exactly 32 bits; fields msb-descending;
  offsets strictly increasing; `attr` ∈ tokens; non-reserved reset must be
  `<width>'<radix><digits>`; reserved must be RO; addrmap name == module
  name == output file base.

## 9. Known limitations

- `CDC` / `Shadow*` / `SetClear` excel columns and RDL props: rejected
  with an explicit error (perl left them half-implemented; not ported).
- One addrmap per file; no signal/field components; no RDL component
  instantiation; regwidth fixed 32.

## 10. Verification invariants

- `tests_edge.py`: 63 tests, all green — attr dispatch across widths,
  std block, auto-append + ExtInt, name magic, v2 FuSa map (placeholder
  resolution, W1C/R alias, RTL shape, defines), error paths, desc
  escaping, xlsx→RDL→v round-trip (model signature equality),
  materialize round-trip, post_autos interop.
- `run_regress.sh`: byte-identical output vs perl ground truths for
  taylor_v3 / taylor_apb_regfile / taylor_v2 (only `^ \* Date :`
  differs).  taylor_apb_regfile runs the simplified flow (functional-only
  xlsx + auto-append + ExtInt); its reference is the perl output on the
  materialized full map.  taylor_apb_regfile_legacy (full hand-written
  map) rides along for the define oracle only.  Every design also runs
  the **define oracle**: perl `--def` vs `rdl2def.py` on the same map —
  all three files byte-identical (modulo Date), DFLT judged separately
  (§11).
- the current map's `.v` (outfile/) + `script/parity_stub.sv` pass a VCS
  compile smoke (`vcs -full64 -sverilog`, elaborates and links).

## 11. Define files (rdl2def.py — port of the perl `--def`)

`rdl2def.py <in.rdl> [-o outdir]` reads the same RDL as rdl2reg.py and
emits, named after the addrmap (module) with the perl's clk_rf name
special cases (`_pre_div_clk_rf`→`_CLK`, `_clk_rf`→`_CLKTOP`):

- `<module>_define.v` — `` `define OFST_<MODULE>_<REG> (32'h%04x) `` per
  register, guard `<MODULE>_DEF_V_`;
- `<module>_define.h` — `#define OFST_<MODULE>_<REG> (0x%04x)`, guard
  `<MODULE>_DEF_H_`;
- `<module>_bit_define.h` — per register `OFST_`/`MASK_`/`DFLT_`
  (`#define %-40s  (%-10s)`; MASK = sw-writable non-reserved bits, DFLT =
  concatenated reset values) plus per-field `BIT_*` / `ATTR_*` macros:
  width-1 → `(BIT_n)`; width>1 → `NAME(_X_) ((_X_) << lsb & (BIT_a
  |BIT_b |...))` with the perl's `BIT_%-2d` trailing-space quirk for
  single-digit bit numbers; full-width `[31:0]` fields and every
  `reserved` field (dedup'd `reserved_1..N` folded back via `rname`)
  get no macros.  Guard reuses `<MODULE>_DEF_H_` (faithful to the perl).

**Documented DFLT divergence**: on maps whose reserved cells hold a bare
`0`, the perl's Reg_value loop-2 reuses a stale radix/digits pair from
the previous field; reg_gen_py normalizes bare `0` to `<width>'h0` at
load (§1) and always emits the clean value.  `_bit_define.h` is compared
modulo `DFLT_` lines; a map where every token parses (e.g. any
`xlsx_materialize.py` output) must match DFLT byte-exactly — enforced by
the regression's strict mode.
