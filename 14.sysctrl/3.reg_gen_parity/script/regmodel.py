#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
regmodel.py -- shared register model + semantics for reg_gen_py.

Single source of truth for the FuSa parity-regfile semantics originally
implemented by reg_gen_parity.pl (v0p3-2023/4/5).  Both front ends
build/inspect this model:

    xlsx --excel2rdl.py--> model --> SystemRDL text
    RDL  --rdl2reg.py----> model --> Verilog (.v.raw)

Everything the perl derived from Excel name magic (ECC region boundary,
PASSWORD / FUSA_CTRL / Mask / Set / Status roles, *_status -> ext_int,
bank membership) is re-derived here from the same rules so both tools
agree by construction.

Python 3.6 compatible (VM rocky-eda: python3.6 + openpyxl 3.1.3).
"""

import re


class RdlError(Exception):
    pass


# original Excel attribute tokens accepted by the perl Attr_check
ATTR_TOKENS = ("RES", "W1S", "W1F", "W1C", "W0S", "W0F", "W0C", "WT",
               "RC", "RW", "MRW", "WO", "MWO", "HW", "RO")

# attr groups (Attr_check): token -> flag name
ATTR_FLAG = {
    "W1S": "w1s", "W1F": "w1s",
    "W1C": "w1c",
    "W0S": "w0s",
    "W0F": "w0c", "W0C": "w0c",
    "WT": "wt",
    "RC": "rc",
    "RW": "rw", "MRW": "rw", "WO": "rw", "MWO": "rw",
    "HW": "hw",
    "RO": "ro",
}

# attr_com digit order (Attr_check): res,w1s,w1c,w0s,w0c,wt,rc,rw,hw,ro
FLAG_ORDER = ("res", "w1s", "w1c", "w0s", "w0c", "wt", "rc", "rw", "hw", "ro")

# reg_attr single-flag table for wr_attr_com (9 digits, no 'res')
SINGLE_ATTR = {
    "100000000": "W1S",
    "010000000": "W1C",
    "001000000": "W0S",
    "000100000": "W0C",
    "000010000": "WT",
    "000001000": "RC",
    "000000100": "RW",
    "000000010": "HW",
    "000000001": "RO",
}

VALUE_RE = re.compile(r"^(\d*)'([bBoOdDhH])([0-9a-fA-F_xXzZ]+)$")

# standard SystemRDL mapping of the Excel attribute token, for interop
# (the .v generation always keys off the original `attr` token instead):
#   token -> (sw, onwrite, onread)
RDL_SW = {
    "RW": ("rw", None, None), "MRW": ("rw", None, None),
    "WO": ("w", None, None), "MWO": ("w", None, None),
    "RO": ("r", None, None), "RES": ("r", None, None),
    "RC": ("r", None, "rclr"),
    "HW": ("rw", None, None), "WT": ("rw", None, None),
    "W1S": ("rw", "woset", None), "W1F": ("rw", "woset", None),
    "W1C": ("rw", "woclr", None),
    "W0S": ("rw", "wzs", None),
    "W0C": ("rw", "wzc", None), "W0F": ("rw", "wzc", None),
}


def norm_reserved_name(name):
    """reserved / reserved_1 / reserved_2 ... -> the perl 'reserved' name.

    RDL forbids duplicate instance names inside one reg, so excel2rdl
    disambiguates repeated reserved rows as reserved_1, reserved_2 ...
    """
    if name == "reserved" or re.match(r"^reserved_\d+$", name):
        return "reserved"
    return name


def parse_value(token):
    """Split a DefaultValue token like "32'h0badbeef" / "1'b0".

    Returns (radix_char_lc, digits) or None when the token carries no
    <width>'<radix> prefix (the perl then leaves radix undef -> zeros).
    """
    m = VALUE_RE.match(token or "")
    if not m:
        return None
    return (m.group(2).lower(), m.group(3))


def value_int(token, width):
    """Numeric value of a DefaultValue token masked to `width` bits.

    Mirrors Reg_value loop-2 sprintf('%0*b', width, val); binary tokens
    with more than one significant digit are evaluated properly (the
    perl numified them -- only all-zero tokens occur in practice).
    """
    pr = parse_value(token)
    if pr is None:
        return 0
    radix, digits = pr
    digits = digits.replace("_", "")
    try:
        if radix == "b":
            val = int(re.sub(r"[xXzZ]", "0", digits), 2)
        elif radix == "o":
            val = int(digits, 8)
        elif radix == "d":
            val = int(digits, 10)
        else:
            val = int(digits, 16)
    except ValueError:
        raise RdlError("bad DefaultValue token %r" % token)
    return val & ((1 << width) - 1)


class Field(object):
    def __init__(self, name, msb, lsb, attr, value, desc="",
                 cdc="", shad="", shadaddr=0, setaddr=0, clraddr=0):
        self.name = name                       # as written in the RDL
        self.rname = norm_reserved_name(name)  # perl-normalized name
        self.msb = int(msb)
        self.lsb = int(lsb)
        self.attr = attr              # original Excel attribute token
        self.value = value            # original DefaultValue token
        # Normalize a bare "0" (reserved rows and plain zero cells in the
        # hand-written tables) to <width>'h0.  The perl keeps the bare token
        # and its Reg_value loop-2 then reuses a STALE radix/digits pair from
        # the previous field (e.g. PASSWORD's 0badbeef leaks into the DFLT
        # macro of the next register).  We never reproduce that: every token
        # that reaches loop-2 parses (same clean-zero result the perl only
        # gets by luck).  This is the ONE intentional define-file divergence.
        if str(self.value).strip() == "0" and parse_value(self.value) is None:
            self.value = "%d'h0" % self.width
        self.desc = desc
        self.cdc = cdc                # unimplemented feature
        self.shad = shad              # unimplemented feature
        self.shadaddr = shadaddr      # unimplemented feature
        self.setaddr = setaddr        # unimplemented feature (setclear)
        self.clraddr = clraddr        # unimplemented feature (setclear)

    @property
    def width(self):
        return self.msb - self.lsb + 1

    def is_reserved(self):
        return self.rname == "reserved"


class Reg(object):
    def __init__(self, gname, offset):
        self.gname = gname     # register name (Excel "Register Name")
        self.offset = offset   # normalized lowercase token, e.g. "04h"
        self.fields = []
        # -- derived by Module.derive() --
        self.flags = {}        # flag -> 0/1 (incl 'res')
        self.wr_flags = ""     # 9-digit string (no 'res')
        self.attr_com = ""     # "r,w,s,..." perl display format
        self.reg_attr = ""     # RES/W1S/W1C/.../MIX
        self.ecc = False       # offset >= ecc_offset
        self.shad_flag = 0
        self.shadaddr = 0

    # ---- offset helpers -------------------------------------------------
    @property
    def offset_int(self):
        return int(self.offset.rstrip("hH"), 16)

    @property
    def gname_uc(self):
        return self.gname.upper()

    # ---- perl name-magic (kept verbatim, semantics are load-bearing) ----
    def is_password(self):
        return self.gname == "PASSWORD"

    def is_fusa_ctrl(self):
        return self.gname.startswith("FUSA_CTRL")

    def is_mask(self):
        # perl /Mask\d*$/ -- 'Mask' at end, optional digits
        return re.search(r"Mask\d*$", self.gname) is not None

    def is_fusa_or_mask(self):
        # perl branch-1: /^PASSWORD$|^FUSA_CTRL|Mask\d*$/
        return self.is_password() or self.is_fusa_ctrl() or self.is_mask()

    def is_set(self):
        return re.search(r"Set\d*$", self.gname) is not None

    def is_status(self):
        return re.search(r"Status\d*$", self.gname) is not None

    def skipped_from_bank(self):
        # perl: /^PASSWORD$|Set\d*$|Status\d*$/
        return self.is_password() or self.is_set() or self.is_status()

    def status_set_regname(self):
        # perl: $set = $fname; s/Status/StatusSet/g
        return self.gname.replace("Status", "StatusSet")


class Module(object):
    def __init__(self, name):
        self.name = name        # module/addrmap name == xlsx base name
        self.base_addr = "0x0"  # header BASE_ADDR (macro-def footer only)
        self.addr_width = 13    # header ADDR_WIDTH
        self.bus = "APB3"       # header bus type
        self.reg_num_hdr = 0    # header REG_NUM (informational only)
        self.ecc_offset = 0     # header ECC_OFFSET (inclusive boundary)
        self.regs = []
        self.std_appended = False  # excel2rdl auto-appended the std block
        # -- derived --
        self.ecc_offs = []      # lowercase offset tokens of ecc regs, in order
        self.ext_int = []       # [(name, width)] from *_status ecc fields
        self.func_num_w = 0     # bank array size (Gen_man_def)
        self.reg_num_w = 0      # count of non-RO/RES regs
        self.ecc_num_w = 0
        self.fusa_ctrl_mask = 0
        self.has_passwd = False # a PASSWORD register exists (gating source)

    # ------------------------------------------------------------------ --
    def derive(self):
        """Attr_check + ecc classification + ext_int + bank accounting."""
        # Attr_check: per-reg flag aggregation
        for reg in self.regs:
            flags = dict.fromkeys(FLAG_ORDER, 0)
            for f in reg.fields:
                if f.rname == "reserved":
                    flags["res"] = 1
                else:
                    if f.attr not in ATTR_TOKENS:
                        raise RdlError("REG %s field %s: unknown attribute %r"
                                       % (reg.gname, f.name, f.attr))
                    flags[ATTR_FLAG[f.attr]] = 1
                if f.shad:
                    reg.shad_flag = 1
                    reg.shadaddr = f.shadaddr
            reg.flags = flags
            reg.attr_com = ",".join(str(flags[k]) for k in FLAG_ORDER)
            full = "".join(str(flags[k]) for k in FLAG_ORDER)
            reg.wr_flags = full[1:]  # drop leading 'res' digit
            if full == "1000000000":
                reg.reg_attr = "RES"
            else:
                reg.reg_attr = SINGLE_ATTR.get(reg.wr_flags, "MIX")

        # ecc region: offsets >= ECC_OFFSET (Proc_info; offsets increase)
        for reg in self.regs:
            reg.ecc = reg.offset_int >= self.ecc_offset
            if reg.ecc:
                self.ecc_offs.append(reg.offset)
        # strictly increasing offset check (Proc_info R645)
        for a, b in zip(self.regs, self.regs[1:]):
            if b.offset_int <= a.offset_int:
                raise RdlError("offsets must strictly increase: %s then %s"
                               % (a.offset, b.offset))

        # Gen_man_def accounting.  The perl formula (reg_num_w - ecc_num_w +
        # fusa_ctrl_mask) implicitly assumes every ecc reg that is neither
        # FUSA_CTRL nor Mask is Set*/Status* -- i.e. bank-skipped.  It
        # OVER-provisions on maps whose std block sits outside the ECC region
        # (fewer members than the formula; the oversized bank arrays are part
        # of the byte-exact legacy output) and UNDER-provisions on v2 FuSa
        # maps (ecc bank members such as STA_PAR / CFG_REGST).  func_num_w
        # takes the max: byte-identical to the perl wherever the perl was
        # right, and always big enough to index every bank member.
        self.reg_num_w = sum(1 for r in self.regs
                             if r.reg_attr not in ("RO", "RES"))
        self.ecc_num_w = sum(1 for r in self.regs
                             if r.ecc and r.reg_attr not in ("RO", "RES"))
        self.fusa_ctrl_mask = sum(1 for r in self.regs
                                  if r.ecc and (r.is_fusa_ctrl() or r.is_mask()))
        self.func_num_w = max(
            self.reg_num_w - self.ecc_num_w + self.fusa_ctrl_mask,
            len(self.bank_regs()))
        # passwd gating exists only when a PASSWORD register stores the key;
        # without one the perl would reference an undeclared passwd forever
        # (compile error) -- rdl2reg omits the gating instead.
        self.has_passwd = any(r.is_password() for r in self.regs)
        if self.func_num_w <= 0:
            raise RdlError("no parity bank registers (func_num_w=%d)"
                           % self.func_num_w)

        # Gen_rtl_iop: ext_int collection (field order, ecc *_status fields)
        names_seen = set()
        for reg in self.regs:
            for f in reg.fields:
                if (reg.ecc and f.rname.endswith("_status")
                        and f.rname not in ("parity_err_status", "reserved")):
                    name = f.rname[:-len("_status")]
                    self.ext_int.append((name, f.width))
                    if name in names_seen:
                        raise RdlError("duplicate *_status field %r" % f.rname)
                    names_seen.add(name)

        # Gen_reg_file: every ext int needs <int>_mask and <int>_set fields
        all_fields = [f.rname for r in self.regs for f in r.fields]
        for name, _w in self.ext_int:
            if (name + "_mask") not in all_fields:
                raise RdlError("A %s_mask must be added for the %s_status "
                               "enable." % (name, name))
            if (name + "_set") not in all_fields:
                raise RdlError("A %s_set must be added for the %s_status "
                               "value set." % (name, name))

    # ------------------------------------------------------------------ --
    def bank_regs(self):
        """Ordered bank members: non-RO/RES, not PASSWORD/Set/Status."""
        return [r for r in self.regs
                if r.reg_attr not in ("RO", "RES") and not r.skipped_from_bank()]

    def bank_index(self, reg):
        return self.bank_regs().index(reg)

    def reg_w_regs(self):
        """Ordered non-RO/RES regs (Reg_value loop-1 list incl skipped)."""
        return [r for r in self.regs if r.reg_attr not in ("RO", "RES")]

    def ecc_first_offset(self):
        return self.ecc_offs[0] if self.ecc_offs else None

    def validate(self):
        if self.bus != "APB3":
            raise RdlError("only bus_type APB3 is supported (got %r)"
                           % self.bus)
        for reg in self.regs:
            bits = sum(f.width for f in reg.fields)
            if bits != 32:
                # name the uncovered / overlapping ranges so the fix is
                # obvious (hand-drawn sketches often leave a gap implicit)
                cover = [0] * 32
                for f in reg.fields:
                    for b in range(f.lsb, f.msb + 1):
                        cover[b] += 1
                holes, dups = [], []
                b = 0
                while b < 32:
                    if cover[b] == 1:
                        b += 1
                        continue
                    kind = holes if cover[b] == 0 else dups
                    hi = b
                    while hi + 1 < 32 and cover[hi + 1] == cover[b]:
                        hi += 1
                    kind.append("[%d]" % b if hi == b
                                else "[%d:%d]" % (hi, b))
                    b = hi + 1
                detail = ""
                if holes:
                    detail += "; missing: " + ", ".join(holes)
                if dups:
                    detail += "; overlapping: " + ", ".join(dups)
                raise RdlError("REG %s: field bits sum to %d (must be 32%s)"
                               % (reg.gname, bits, detail))
            for f in reg.fields:
                if f.rname == "reserved" and f.attr != "RO":
                    raise RdlError("REG %s: reserved field %s must be RO"
                                   % (reg.gname, f.name))
                if f.rname != "reserved" and parse_value(f.value) is None:
                    raise RdlError("REG %s field %s: DefaultValue %r must be "
                                   "<width>'<radix><digits>"
                                   % (reg.gname, f.name, f.value))
                if f.cdc or f.shad or f.shadaddr or f.setaddr or f.clraddr:
                    raise RdlError(
                        "REG %s field %s: cdc/shadow/setclear features are "
                        "not supported by this generator yet"
                        % (reg.gname, f.name))
                if not 0 <= f.lsb <= f.msb <= 31:
                    raise RdlError("REG %s field %s: bad bit range [%s:%s]"
                                   % (reg.gname, f.name, f.msb, f.lsb))
        # fields must appear in descending msb order
        for reg in self.regs:
            prev_msb = 32
            for f in reg.fields:
                if f.msb >= prev_msb:
                    raise RdlError("REG %s field %s: bits not descending"
                                   % (reg.gname, f.name))
                prev_msb = f.msb


# ----------------------------------------------------------------------------
# Standard FuSa block -- fusa_std_block.md v1.0 (auto-appended by excel2rdl)
# -----------------------------------------------------------------------------

def std_block_regs(ecc_offset, ext_ints=()):
    """The five standard FuSa registers at [ecc_offset, ecc_offset+0x14].

    Layout (v1.0, fixed): PASSWORD@+0x0, FUSA_CTRL@+0x4,
    MIssionIntStatusSet0@+0x8, MIssionIntStatus0@+0xc, MIssionIntMask0@+0x10.
    bit0 of Set/Status/Mask is always parity_err; ext faults are allocated
    bottom-up from bit1 (a multi-bit fault takes a contiguous field).

    ext_ints: [(name, width)] in msb-descending order -- the FIRST entry
    gets the HIGHEST bit (matches the excel msb->lsb row convention).
    """
    ext_ints = [(n, int(w)) for n, w in ext_ints]
    nbits = 1 + sum(w for _n, w in ext_ints)
    if nbits > 32:
        raise RdlError("standard block ext ints use %d bits (cap 31)"
                       % (nbits - 1))

    def F(name, msb, lsb, attr, value, desc=""):
        return Field(name, msb, lsb, attr, value, desc=desc)

    def vt(w):
        return "%d'b0" % w

    def R(gname, off, fields):
        r = Reg(gname, "%02xh" % (ecc_offset + off))
        r.fields = fields
        return r

    regs = [R("PASSWORD", 0x0, [
        F("passwd", 31, 0, "RW", "32'h0badbeef",
          "write key; 0x95f2d303 unlocks 0x08~0x14 writes")])]

    regs.append(R("FUSA_CTRL", 0x4, [
        F("reserved", 31, 13, "RO", "0"),
        F("parity_invert", 12, 12, "RW", vt(1),
          "parity invert injection (SW, 2-cycle window, all banks)"),
        F("parity_fault_injection", 11, 8, "RW", vt(4),
          "parity pattern injection (gated by fault_injection_en)"),
        F("reserved_1", 7, 4, "RO", "0"),
        F("lockstep_fault_injection", 3, 2, "RW", vt(2),
          "lockstep compare injection pattern"),
        F("fault_injection_en", 1, 1, "RW", vt(1),
          "injection master enable"),
        F("parity_decoder_enable", 0, 0, "RW", vt(1),
          "0 = decoder bypass (fail-visible)")]))

    def trio(suffix, attr, gname, off, desc):
        fields = []
        if nbits <= 31:
            fields.append(F("reserved", 31, nbits, "RO", "0"))
        bit = nbits - 1
        for name, w in ext_ints:          # first entry = highest bit
            fields.append(F(name + suffix, bit, bit - w + 1, attr, vt(w),
                            desc))
            bit -= w
        fields.append(F("parity_err" + suffix, 0, 0, attr, vt(1)))
        return R(gname, off, fields)

    regs.append(trio("_set", "WO", "MIssionIntStatusSet0", 0x8,
                     "software set (F5 simulated fault)"))
    regs.append(trio("_status", "W1C", "MIssionIntStatus0", 0xc,
                     "sticky status; hw set wins over W1C"))
    regs.append(trio("_mask", "RW", "MIssionIntMask0", 0x10,
                     "output mask (does not clear status)"))
    return regs
