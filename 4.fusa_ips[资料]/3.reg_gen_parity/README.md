# reg_gen_parity — 寄存器奇偶加固自动生成(horizon 方案 python 化)

Excel 寄存器表 → SystemRDL → 带奇偶保护的 APB regfile RTL + C/Verilog 宏文件,
一条命令完成。python 工具链(`script/`)是 horizon `reg_gen_parity.pl`
(v0p3-2023/4/5,原件保留在 `script/reg_gen_parity.pl`)的完整移植,
生成结果与 perl **字节级一致**(modulo `* Date :` 头行),已四设计回归验证。

## 目录管理

```
reg_gen_parity/
├── gen_regfile.sh        # 一条命令入口(本目录下直接运行)
├── README.md             # 本使用说明
├── regfile_table/        # 寄存器文件说明 excel 表(输入)
│   └── taylor_apb_regfile.xlsx
├── script/               # 全部脚本
│   ├── excel2rdl.py      #   xlsx → SystemRDL(自动追加标准块/解析 v2 占位)
│   ├── rdl2reg.py        #   RDL → .v.raw
│   ├── post_autos.py     #   .v.raw → .v(autoarg/autowire/autoreg 后处理)
│   ├── rdl2def.py        #   RDL → _define.v / _define.h / _bit_define.h
│   ├── regmodel.py       #   共享寄存器模型(单一事实源)
│   ├── xlsx_materialize.py # 追加块物化回全量表(perl 互操作/评审)
│   ├── tests_edge.py     #   63 项边界测试
│   ├── run_regress.sh    #   字节级回归(perl ground truth + --def oracle)
│   ├── parity_stub.sv    #   parity_enc/dec 功能替身(编译冒烟用)
│   ├── reg_gen_parity.pl #   horizon 原始 perl(存档,未打补丁)
│   └── regress/          #   回归 fixtures(历史设计 xlsx + perl 基准 .v)
├── outfile/              # 生成的文件(rdl + .v + 3 个 define 文件)
├── doc/                  # 说明文档(SPEC/标准块定义/生成实例说明)
└── log/                  # 每次 gen 的运行记录(<时间戳>_<模块名>.log)
```

## 使用

VM rocky-eda(工具链依赖 python3+openpyxl,本机 Windows 无环境),在
reg_gen_parity/ 目录下,子命令式:

```bash
bash gen_regfile.sh                    # 无参数 = 显示 help
bash gen_regfile.sh run regfile_table/taylor_apb_regfile.xlsx
#   -> outfile/taylor.rdl
#      outfile/taylor_apb_regfile.v
#      outfile/taylor_apb_regfile_define.v        (`define OFST_*)
#      outfile/taylor_apb_regfile_define.h        (#define OFST_*)
#      outfile/taylor_apb_regfile_bit_define.h    (OFST/MASK/DFLT/BIT/ATTR)
#      log/<时间戳>_taylor.log                    (完整运行记录+自检结果)
#   可选 -o <dir> 改输出目录;脚本自带 PASS/FAIL 自检,退出码即结果
bash gen_regfile.sh clean              # 清除所有过程文件(outfile/ + log/ 内容)
bash gen_regfile.sh regfile_table/xx.xlsx   # 便捷写法, 等价于 run
```

新设计只需把表放进 `regfile_table/` 再跑 run;C 侧直接 include
`_define.h` / `_bit_define.h`。

## 输入表两种写法(excel2rdl.py 自动识别)

1. **只写功能寄存器**(offset < ECC_OFFSET)+ 可选 `ExtInt` sheet(每行一个
   扩展故障):标准 FuSa 块(PASSWORD / FUSA_CTRL / MIssionIntStatusSet0 /
   MIssionIntStatus0 / MIssionIntMask0)在 ECC_OFFSET 处**自动追加**,
   见 [doc/fusa_std_block.md](doc/fusa_std_block.md) v1.0。
2. **手写全量表**(表内出现 ≥ECC_OFFSET 的寄存器即判定,不追加):
   如 v2 三寄存器块 FUSA_CTRL/STA_PAR/CFG_REGST,`n`/`m` 占位符自动定尺寸,
   见 [doc/SPEC.md](doc/SPEC.md) §1.2。

## 验证(改完脚本必跑)

```bash
python3 script/tests_edge.py     # 63/63(临时目录运行,自清理)
bash    script/run_regress.sh    # 4 设计 .v + define 文件字节级一致 +
                                 # perl --def oracle;产物进 /tmp/regress_work
```

回归依赖 VM 上打过补丁的 perl(`~/work/reg_gen_parity/reg_gen_parity.pl`,
`REGGEN_PL` 可覆盖)与 `PERL5LIB=~/perl5/lib/perl5`;缺 perl 时 define oracle
跳过并告警,字节级 .v 比对照常执行。

当前生成实例的说明见 [doc/taylor_apb_regfile.md](doc/taylor_apb_regfile.md);
RDL 子集与生成规则权威定义见 [doc/SPEC.md](doc/SPEC.md)。
