# apb2mbus — APB3 slave → mbus master 桥 (MCP 直采 CDC + FuSa hang 保护)

X7A MCU System / TR4 / MCUSys / FuSa。APB3 从端到 mbus 主端的 CDC 桥，
源自 `2.parity` 仓 (此处为独立归档副本, 原始文件仍在 `2.parity/rtl`)。

- CDC 为 **MCP 直采结构**: 数据通路 (addr/wdata/wr/par/rdata) 直采静态
  保持电平, 不加同步 FF; 同步 FF 只留给两个单 bit 控制 toggle, 一律例化
  标准 `sync_2dff` + `sync_dff` 单元 (FPGA / ASIC 仿真 / ASIC 后端工艺
  cell 三分支, 便于后端替换 hardened sync cell)。
- **命令在途偶校验** `par_q = ^{addr, wr, wdata}`: req_fire 当拍与
  payload 同沿锁存 (APB 域) 后静态直采, 叶端重组比对查在途 1bit 损坏
  (门写 + PERR); 保持寄存器在途 SEU 亦可检出。
- **APB 域 hang 看门狗**: mbus 侧死亡/CDC 断链时 HANG_TO 拍后强制完成
  (pready + SLVERR, CPU 收 bus error 而不是总线挂死), hang_evt 双轨
  脉冲送 ESM; DRAIN 态消化迟到 ack, 链路自愈。
- 越界实例 (paddr[15:8] ≥ NP): 立即 pready + pslverr, 不发起 mbus 传输。

## 目录

| 路径 | 内容 |
|------|------|
| `rtl/` | `apb2mbus.sv` · `sync_2dff.sv` / `sync_dff.sv` (标准同步单元, 三分支) |
| `sim/` | `tb_apb2mbus.sv` (hang 看门狗专项, 28 checks) · `run_vcs.sh` (VCS+Verdi, 在 Rocky VM 跑) · `run_iverilog.sh` (WSL iverilog 兜底) |
| `doc/` | `apb2mbus_design.md` (设计说明: MCP CDC 结构 / hang 看门狗 / SDC 要求 / 参数 / 验证) |

## 仿真

```bash
# Rocky VM (VCS+Verdi, 正式流程)
cd sim && bash run_vcs.sh          # 编译 + 仿真, 产物 obj_vcs/
       bash run_vcs.sh verdi       # Verdi 打开波形
```

相关: 叶端寄存器文件见 `2.parity/rtl/edc_regfile.sv` (parity 比对/PERR14)
与 `5.cmm/rtl/cmm_regfile.sv` (PERR_CMD)。
