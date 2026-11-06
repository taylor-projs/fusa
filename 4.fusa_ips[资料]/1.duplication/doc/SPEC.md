# duplication SPEC — dcls_auto 标记协议与生成规则(权威定义)

> 工具源流: horizon `dcls_auto`(honghe.tan 2019 v0.1 → sen.li 2022 v1.20, py2)→
> **py3 移植修复版 `script/dcls_auto_py3.py`(权威)**; 原始 py2 存档于
> `script/dcls_auto.py`。本文件定义输入标记协议、生成结构与回归判定。

## 0. py3 相对 py2 的修复记录

基础: py2→py3 语法移植(`print`→函数、`cmp()`→`==`)。在此之上修 3 个 bug:

1. **`<clk>_dcls` 端口重复声明 + cell_ckgate 双驱动** — py2 的
   Clockbuffer/IClockbuffer 全局量被多实例覆盖, 多实例共用同一时钟时
   重复生成 `output <clk>_dcls`(直接编不过; 实物见 `demo/test_gld.v`
   第 40-41 行两条 `output mclk_dcls`); py3 改为父模块 `allDclsClks`
   跨实例去重收集(注意: 仅 `-d` 延迟模式生成, 见 §5);
2. **delay=0 实例 err 打拍引用不存在的 `<clk>_dcls`** — 改为 delay=0
   用原时钟打拍;
3. **ANSI output 端口 + 体内 wire 冗余声明 warning** — 已成端口的信号
   不再补 wire 声明。

## 1. 输入标记

| 标记 | 位置 | 含义 |
|---|---|---|
| `/*AUTOFUSADCLS*/` | 实例化行(模块名行或 `) 实例名 (` 行)行尾 | 该实例做 DCLS 双例化 |
| `/*AUTOFUSADCLS+Dx*/` | 同上 | 同上 + 两核间插 x 拍延迟(需 `-d` 选项) |

- 一个文件可标多个实例, 各自独立生成双例 + 比较器;
- 未标记的实例化不动。

## 2. 端口方向注释(标记实例的每行端口尾)

| 标签 | 含义 | 生成行为 |
|---|---|---|
| `//O` / `//OUT...` / `//Output...` | 输出 | 双核输出各引一份进比较器 |
| `//I`(或无注释) | 输入(无注释有 WARNING) | 双核共享驱动 |
| `//MCLK` | 主 DCLS 时钟 | 生成 `output <clk>_dcls` 门控时钟(去重) |
| `//CLK` | 标签时钟(LCLK) | 同上 |
| `//RST` | 复位 | 复位路径特殊处理(随复位方案) |
| `//NOCMP` | 该端口不比较 | 比较器省掉该位(降开销) |
| `//ICG` | 时钟门控使能端口 | 触发生成顶层 `input icg_mode` |
| `//SCAN` / `//FORCEI` / `//FORCEO` | 扫描/强制旁路信号 | 记入工具 scan 集合(FORCEI/FORCEO 走 `_fusadcls_i` 命名) |

无 `()` 连接的输出端口自动按 NC 处理; 常数输入(如 `1'b0`)支持。
工具按正则前缀识别(`O|OUT|Output` 一族 / `MCLK` / `CLK` / `RST` /
`NOCMP` / `ICG` / `SCAN` / `FORCEI` / `FORCEO`), 其余视为输入。
demo 只覆盖 O/I/CLK/MCLK/RST/NOCMP; SCAN/ICG/FORCEI/FORCEO 与
「LCLK+D0 组合生成 `_buf` 未声明」为**未踩路径**, 用到时先冒烟。

## 3. 生成结构

- 全部生成内容包在 `/********__AutoGenFuSaDCLS_Start__********/` …
  `/*********__AutoGenFuSaDCLS_End__*********/` 之间, 外套 `` `ifdef FUSA ``;
  源文件其余内容原样保留(`-c` 选项可移除生成块, 恢复干净输入);
- 顶层新增端口:
  - `input [1:0] dcls_fault_injection` — 2bit 编码注错(最高位=比较器注错);
  - `output <clk>_dcls` — 每个标签时钟一份(跨实例去重), 门控后的 DCLS 时钟;
  - `input icg_mode` — 时钟门控模式;
  - `output reg err_fusadcls_<实例名>` — 每个标记实例一路错误输出
    (`-s` subtop 模式下打包为 `err_dcls[]` 总线, 供上层再聚合);
- 每个标记实例生成 `<实例名>_fusadcls` 双例化 + 一个 `fusa_comparator`
  (比较器单元源码 `script/fusa_comparator.v`, 集成时随生成文件一起拷贝);
- 延迟模式(`+Dx` + `-d`): 两核间插 x 拍, 延迟信号带复位初值;
- 选项: `-d` 延迟 / `-s` subtop / `--fusaclk` 独立 fusa 时钟 / `-c` 清除生成块 /
  `-o <file>` 指定输出(gen_dcls.sh 恒用 `-o`, 源文件永不回写)。

## 4. 编码约束(输入必须满足)

1. **端口连接行行尾禁 `);`** — 实例化收尾括号必须独立成行。工具按行扫描识别
   实例化块结束, 行尾 `);` 会破坏解析(design/test.v→test_fix.v 第 75-76 行
   即该约束的修正样例);
2. 输入须为工具可解析的 **Verilog-2001 子集**(模块/例化/端口/参数语法);
   SystemVerilog 仓(struct、logic、always_ff 等)**不适用**;
3. TB 对生成模块内部信号的 `force` 必须放在 `initial` 块内。

## 5. 回归判定(gen_dcls.sh regress)

1. **字节级**: `design/test_fix.v` **加 `-d`** 复算输出 == `outfile/test_dcls.v`
   (基准为延迟模式产物: `+D1/+D2` 标记需配 `-d`, 且 `*_dcls` 时钟输出端口的
   跨实例去重仅在 `-d` 下生成 — 不带 `-d` 会少掉 `output mclk_dcls/pclk_dcls`);
2. **冒烟**: VCS `+define+FUSA` 编译运行 `demo/tb_dcls.v`
   (跑的是 1) 的**复算产物** + fusa_comparator.v + dummy_modules.v), 判定
   `TB PASS: all checks passed` 且无 `FAIL ` 行 — 覆盖三态:
   T1 正常无错 → T2 `dcls_fault_injection=01` 三路 err 置起 → T3 撤销自愈;
3. `demo/test_gld.v` 为 py2 原始输出**存档对照**(含 §0-2 的 bug), 不作基准。

冒烟波形可用 `script/vcd_probe2.py dcls.vcd '<正则>'` 速查关键信号
(en_dcls/mclk_dcls/fault_injection/err_fusadcls...)。
