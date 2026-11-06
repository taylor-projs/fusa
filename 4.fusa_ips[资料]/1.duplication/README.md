# duplication — DCLS 双核锁步自动生成(horizon dcls_auto python3 修复版)

对带 `/*AUTOFUSADCLS*/` 标记的 Verilog 设计, 一条命令生成 DCLS 双例化 +
`fusa_comparator` 比较的加固代码(全部内嵌在 `` `ifdef FUSA `` 块内, 原功能不动,
不加 FUSA 宏编译即回到原设计)。权威工具为 `script/dcls_auto_py3.py`
(horizon 原始 py2 的移植修复版, 原件存档 `script/dcls_auto.py`)。

## 目录管理

```
1.duplication/
├── gen_dcls.sh            # 一条命令入口(本目录下直接运行)
├── README.md              # 本使用说明
├── design/                # 输入设计(带 AUTOFUSADCLS 标记 + 端口方向注释)
│   ├── test.v             #   horizon 原始 demo 输入(违反行尾约束, 存档对照)
│   └── test_fix.v         #   约束修正后的输入(回归基准)
├── script/                # 全部脚本 + 配套单元
│   ├── dcls_auto_py3.py   #   主工具(py3 修复版, 权威)
│   ├── dcls_auto.py       #   horizon 原始 py2(存档, 未打补丁)
│   ├── fusa_comparator.v  #   生成代码例化的比较器单元(集成时随生成文件拷走)
│   └── vcd_probe2.py      #   VCD 波形探针(dcls 关键信号速查)
├── outfile/               # 生成文件(test_dcls.v = 回归基准产物)
├── demo/                  # 端到端冒烟
│   ├── dummy_modules.v    #   被保护的示例子模块(example/exam/exam2 + cell)
│   ├── tb_dcls.v          #   冒烟 TB(注错→err 置起→撤销自愈)
│   └── test_gld.v         #   py2 原始输出存档(含时钟重复声明 bug, 仅对照非基准)
├── doc/                   # 说明文档(标记/注释协议权威定义)
└── log/                   # 每次 gen 的运行记录(<时间戳>_<模块名>.log)
```

## 使用

VM rocky-eda 上运行(生成需 python3; 冒烟需 VCS; 本机 Windows 无环境),
在 `1.duplication/` 目录下, 子命令式:

```bash
bash gen_dcls.sh                                # 无参数 = 显示 help
bash gen_dcls.sh run design/xx.v                # -> outfile/xx_dcls.v (源文件不回写)
bash gen_dcls.sh run design/xx.v -d             # 延迟插入模式(标记写 /*AUTOFUSADCLS+Dx*/)
bash gen_dcls.sh run design/xx.v -s             # subtop 模式: err_fusadcls_* 打包 err_dcls[]
bash gen_dcls.sh run design/xx.v --fusaclk      # 双核用独立 fusa 时钟
bash gen_dcls.sh run design/xx.v -o <dir>       # 改输出目录(默认 outfile/)
bash gen_dcls.sh xx.v                           # 便捷写法, 等价于 run
bash gen_dcls.sh regress                        # 字节级回归 + demo VCS 冒烟(改完脚本必跑)
bash gen_dcls.sh clean                          # 清除 outfile/ + log/ 过程文件
```

脚本自带 PASS/FAIL 自检(标记块/宏保护/注错端口/比较器与 err 数量对账),
退出码即结果; 完整运行记录进 `log/`。

## 新设计接入三步

1. 把设计 .v 拷进 `design/`, 在要加固的实例化行尾加 `/*AUTOFUSADCLS*/`
   (延迟插一格写 `/*AUTOFUSADCLS+D1*/` 并配 `-d`);
2. 该实例化的每行端口尾补方向注释(见下), 跑 `bash gen_dcls.sh run design/xx.v`;
3. 集成: `outfile/xx_dcls.v` + `script/fusa_comparator.v` 一起拷进目标仓,
   编译选项加 `+define+FUSA`(不加则原样), 顶层连 `dcls_fault_injection`/`err_fusadcls_*`。

端口方向注释(`//` 后的标签, 详见 [doc/SPEC.md](doc/SPEC.md) §2):

| 标签 | 含义 |
|---|---|
| `//O`(或 OUT/Output 前缀) | 输出端口(参与比较; 空 `()` 连接 = NC) |
| `//I`(可省, 无注释默认输入) | 输入端口 |
| `//CLK` / `//MCLK` | 标签时钟 / 主 DCLS 时钟(生成对应 `*_dcls` 输出) |
| `//RST` | 复位端口 |
| `//NOCMP` | 该端口不参与比较(省比较器开销) |

## 编码约束(输入必须满足, 详见 SPEC §4)

- 端口连接行行尾**禁 `);`** — 收尾括号必须独立成行(design/test.v 第 75 行
  即违反样例, test_fix.v 为修正后形态);
- 输入需为工具可解析的 Verilog-2001 子集, **SV 仓不适用**;
- TB 中对生成模块内部信号的 `force` 必须放在 `initial` 块内。

## 验证(改完脚本必跑)

```bash
bash gen_dcls.sh regress
#   1) design/test_fix.v 加 -d 复算(基准为延迟模式产物), 与 outfile/test_dcls.v 字节级一致
#   2) demo 冒烟: VCS +define+FUSA 编译运行 tb_dcls.v(跑复算产物) ->
#      "TB PASS: all checks passed" (T1 正常无错 / T2 fi=01 注错 err 置起 / T3 撤销自愈)
```

demo/test_gld.v 是 **py2 原始工具的输出存档**(第 40-41 行可见 `output mclk_dcls`
重复声明, 即 py3 修复的 bug 实物), 只作历史对照, 不参与回归判定。
标记语法与生成结构的权威定义见 [doc/SPEC.md](doc/SPEC.md)。
