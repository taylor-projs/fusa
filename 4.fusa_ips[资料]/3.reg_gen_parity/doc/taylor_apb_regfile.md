# taylor_apb_regfile — 生成实例说明

输入 [regfile_table/taylor_apb_regfile.xlsx](../regfile_table/taylor_apb_regfile.xlsx)
(v1.0 标准块布局的**手写全量表**,2026-11-06 用户正式版):

| Offset | 寄存器 | 说明 |
| --- | --- | --- |
| 0x000 | REG_CFG0 | 功能寄存器(cpu_idle_cfg RW 32'h0),passwd 不设防 |
| 0x100 | PASSWORD | 写钥匙(复位 32'h0badbeef = 上锁) |
| 0x104 | FUSA_CTRL | parity_invert / parity_fault_injection[3:0] / lockstep_fault_injection[1:0] / fault_injection_en / parity_decoder_enable |
| 0x108 | MIssionIntMask0 | 7 个 `_mask` 字段,**复位全 1'b1**(默认屏蔽) |
| 0x10C | MIssionIntStatusSet0 | 7 个 `_set` WO 软件置位 |
| 0x110 | MIssionIntStatus0 | 7 个 `_status` W1C 粘滞状态 |

表头 `ECC_OFFSET:0x100`;表内已含 PASSWORD/≥ECC_OFFSET 寄存器 →
判定手写全量表,**不追加**标准块(与 [fusa_std_block.md](fusa_std_block.md)
v1.0 行定义一致)。

## 复现(VM rocky-eda,reg_gen_parity/ 根目录)

```bash
bash gen_regfile.sh run regfile_table/taylor_apb_regfile.xlsx
#   bash gen_regfile.sh clean  可清空 outfile/ + log/ 后重跑
```

产物在 [outfile/](../outfile/),运行记录在
[log/](../log/)<时间戳>_taylor.log(2026-11-06 生成:全部自检 PASS、
VCS 编译冒烟通过、与改版前输出比对仅 Date 头行不同):

| 文件 | 内容 |
| --- | --- |
| `taylor.rdl` | SystemRDL 中间真源 |
| `taylor_apb_regfile.v` | APB regfile RTL |
| `taylor_apb_regfile_define.v` | Verilog 宏(`` `define OFST_* ``) |
| `taylor_apb_regfile_define.h` | C 偏移宏(`#define OFST_*`) |
| `taylor_apb_regfile_bit_define.h` | C 偏移/掩码/复位值/位段宏(OFST/MASK/DFLT/BIT/ATTR) |

VCS 冒烟(编译+elaborate):

```bash
vcs -full64 -sverilog outfile/taylor_apb_regfile.v script/parity_stub.sv \
    -top taylor_apb_regfile -o /tmp/simv
```

## 本表生成要点

- **parity bank 3 成员** = REG_CFG0 / FUSA_CTRL / MIssionIntMask0
  (PASSWORD/Set0/Status0 按名字规则不进 bank);`parity_dec_error [2:0]`。
  注意 Mask0 是 bank 成员:屏蔽位本身受奇偶保护、写需 passwd。
- **passwd 门控生效**:0x104~0x110 全部写操作带
  `&& (passwd==32'h95f2d303)`(共 4 处),复位后锁死,写 PASSWORD 解锁。
- **Mask0 复位全 1** → `MASK/DFLT_..._MISSIONINTMASK0 = 0x0000007F`;
  `MASK_..._FUSA_CTRL = 0x00001F0F`、DFLT 全 0;Status0 复位全 0。
- **6 个扩展中断**由 MIssionIntStatus0 的 `_status` 字段派生(bit6→bit1:
  pd_top_noc_idlereq_time_out / pd_top_bisr_done_time_out /
  pd_top_bisr_busy_time_out / pd_top_pwr_off_time_out /
  top_pmu_signal_chk_err / lockstep_err;bit0 = parity_err),各出
  `<int>_err` 打拍输出 + `mission_int`。
- FUSA_CTRL [15:14] 与 [13] 为 reserved 行(2026-11-06 表内描述已删):
  不产生 BIT/ATTR 宏、读写无效。要成为可操作字段需给真实字段名
  (如 `cpu_mode_switch[15:14] RW 2'b0`),改表重跑即可。

设计侧后续(端口已备好,逻辑属各 IP):六个故障源的
`<int>_status_wr/_in` 硬件置位连线。
