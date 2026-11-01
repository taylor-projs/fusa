# Generate WWDT (DW_apb_wdt) register table Excel file
$ErrorActionPreference = 'Stop'

$outPath = Join-Path $PSScriptRoot 'wwdt_registers.xlsx'
if (Test-Path $outPath) { Remove-Item $outPath -Force }

# Register groups: Offset, RegName, Fields[] = @(SubBits, FieldName, Attr, Default, Description)
$regs = @(
  @{ Offset='000h'; Reg='WDT_CR'; Fields=@(
    @('[31:8]','reserved','RO','0',''),
    @('[7]','WDT_CPU_HALT_EN','RW','1''h0',"cpu debug mode enable.`n1'b1: cpu debug mode enable`n1'b0: cpu debug mode disable"),
    @('[6]','INT_SECOND_EN','RW','1''h0',"Second Interrupt enable`n1'b1: second interrupt enable`n1'b0: second interrupt disable"),
    @('[5]','INT_EN','RW','1''h0',"Interrupt enable`n1'b1: interrupt enable`n1'b0: interrupt disable"),
    @('[4:2]','RPL','RW','3''h0',"Reset pulse length.`nWrites have no effect when the configuration parameter WDT_HC_RPL is 1, making the register bits read-only. This is used to select the number of pclk cycles for which the system reset stays asserted. The range of values available is 2 to 256 pclk cycles.`nNote: When WDT_ASYNC_CLK_MODE_ENABLE = 1, the total reset pulse length also includes the reset synchronization delay and the time taken for pclk to be made available. For details, refer to `"System Resets`" section of DW_apb_wdt Databook.`n`nValues:`n0x0 (PCLK_CYCLES_2): 2 pclk cycles`n0x1 (PCLK_CYCLES_4): 4 pclk cycles`n0x2 (PCLK_CYCLES_8): 8 pclk cycles`n0x3 (PCLK_CYCLES_16): 16 pclk cycles`n0x4 (PCLK_CYCLES_32): 32 pclk cycles`n0x5 (PCLK_CYCLES_64): 64 pclk cycles`n0x6 (PCLK_CYCLES_128): 128 pclk cycles`n0x7 (PCLK_CYCLES_256): 256 pclk cycles"),
    @('[1]','RMOD','RW','1''h1',"Response mode.`nWrites have no effect when the parameter WDT_HC_RMOD = 1, thus this register becomes read-only. Selects the output response generated to a timeout.`n`nValues:`n0x0 (RESET): Generate a system reset`n0x1 (INTERRUPT): First generate an interrupt and even if it is cleared by the time a second timeout occurs then generate a system reset"),
    @('[0]','WDT_EN','RW','1''h0',"WDT enable.`nWhen the configuration parameter WDT_ALWAYS_EN = 0, this bit can be set; otherwise, it is read-only. This bit is used to enable and disable the DW_apb_wdt. When disabled, the counter does not decrement. Thus, no interrupts or system resets are generated.`nThe DW_apb_wdt is used to prevent system lock-up. To prevent a software bug from disabling the DW_apb_wdt, once this bit has been enabled, it can be cleared only by a system reset.`n`nValues:`n0x0 (DISABLED): Watchdog timer disabled`n0x1 (ENABLED): Watchdog timer enabled")
  )},
  @{ Offset='004h'; Reg='WDT_TORR'; Fields=@(
    @('[31:8]','reserved','RO','0',''),
    @('[7:4]','RSVD_TOP_INIT','RO','4''h0','WDT TORR[7:4] Reserved field for TOP INIT'),
    @('[3:0]','TOP','RW','4''h0',"Writes have no effect when the configuration parameter WDT_HC_TOP=1, thus making this register read-only. This field is used to select the timeout period from which the watchdog counter restarts. A change of the timeout period takes effect only after the next counter restart (kick).`nThe range of values is limited by the WDT_CNT_WIDTH. If TOP is programmed to select a range that is greater than the counter width, the timeout period is truncated to fit to the counter width. This affects only the non-user specified values as users are limited to these boundaries during configuration.`nThe range of values available for a 32-bit watchdog counter are:`nWhere i = TOP and t = timeout period`nFor i = 0 to 15`nif WDT_USE_FIX_TOP==1`nt = 2^(16 + i)`nelse`nt = WDT_USER_TOP_(i)`n`nValues:`n0x0 (USER0_OR_64K): Time out of WDT_USER_TOP_0 or 64K Clocks`n0x1 (USER1_OR_128K): Time out of WDT_USER_TOP_1 or 128K Clocks`n0x2 (USER2_OR_256K): Time out of WDT_USER_TOP_2 or 256K Clocks`n0x3 (USER3_OR_512K): Time out of WDT_USER_TOP_3 or 512K Clocks`n0x4 (USER4_OR_1M): Time out of WDT_USER_TOP_4 or 1M Clocks`n0x5 (USER5_OR_2M): Time out of WDT_USER_TOP_5 or 2M Clocks`n0x6 (USER6_OR_4M): Time out of WDT_USER_TOP_6 or 4M Clocks`n0x7 (USER7_OR_8M): Time out of WDT_USER_TOP_7 or 8M Clocks`n0x8 (USER8_OR_16M): Time out of WDT_USER_TOP_8 or 16M Clocks`n0x9 (USER9_OR_32M): Time out of WDT_USER_TOP_9 or 32M Clocks`n0xa (USER10_OR_64M): Time out of WDT_USER_TOP_10 or 64M Clocks`n0xb (USER11_OR_128M): Time out of WDT_USER_TOP_11 or 128M Clocks`n0xc (USER12_OR_256M): Time out of WDT_USER_TOP_12 or 256M Clocks`n0xd (USER13_OR_512M): Time out of WDT_USER_TOP_13 or 512M Clocks`n0xe (USER14_OR_1G): Time out of WDT_USER_TOP_14 or 1G Clocks`n0xf (USER15_OR_2G): Time out of WDT_USER_TOP_15 or 2G Clocks")
  )},
  @{ Offset='008h'; Reg='WDT_CCVR'; Fields= ,@('[31:0]','WDT_CCVR','RO','32''hffffffff',"WDT Current Counter Value Register.`nThis register, when read, is the current value of the internal counter. This value is read coherently when ever it is read, which is relevant when the APB_DATA_WIDTH is less than the counter width.")},
  @{ Offset='00ch'; Reg='WDT_CRR'; Fields=@(
    @('[31:8]','reserved','RO','0',''),
    @('[7:0]','WDT_CRR','WO','8''h0',"Counter Restart Register.`nThis register is used to restart the WDT counter. As a safety feature to prevent accidental restarts, the value 0x76 must be written. A restart also clears the WDT interrupt.`nReading this register returns zero.`n`nValues:`n0x76 (RESTART): Watchdog timer restart command")
  )},
  @{ Offset='010h'; Reg='WDT_STAT'; Fields=@(
    @('[31:1]','reserved','RO','0',''),
    @('[0]','WDT_STAT','RO','1''h0',"Interrupt status register`nThis register shows the interrupt status of the WDT.`n`nValues:`n0x0 (INACTIVE): Interrupt is inactive`n0x1 (ACTIVE): Interrupt is active regardless of polarity")
  )},
  @{ Offset='014h'; Reg='WDT_EOI'; Fields=@(
    @('[31:1]','reserved','RO','0',''),
    @('[0]','WDT_EOI','RO','1''h0','Interrupt Clear Register.`nClears the watchdog interrupt. This can be used to clear the interrupt without restarting the watchdog counter.')
  )},
  @{ Offset='0e4h'; Reg='WDT_COMP_PARAM_5'; Fields= ,@('[31:0]','CP_WDT_USER_TOP_MAX','RO','32''hffffffff','Upper limit of Timeout Period parameters. The value of this register is derived from the WDT_USER_TOP_* coreConsultant parameters.')},
  @{ Offset='0e8h'; Reg='WDT_COMP_PARAM_4'; Fields= ,@('[31:0]','CP_WDT_USER_TOP_INIT_MAX','RO','32''h0','Upper limit of Initial Timeout Period parameters. The value of this register is derived from the WDT_USER_TOP_INIT_* coreConsultant parameters.')},
  @{ Offset='0ech'; Reg='WDT_COMP_PARAM_3'; Fields= ,@('[31:0]','CD_WDT_TOP_RST','RO','32''h0','The value of this register is derived from the WDT_TOP_RST coreConsultant parameter.')},
  @{ Offset='0f0h'; Reg='WDT_COMP_PARAM_2'; Fields= ,@('[31:0]','CP_WDT_CNT_RST','RO','32''hffffffff','The value of this register is derived from the WDT_RST_CNT coreConsultant parameter.')},
  @{ Offset='0f4h'; Reg='WDT_COMP_PARAM_1'; Fields=@(
    @('[31:29]','reserved','RO','0',''),
    @('[28:24]','WDT_CNT_WIDTH','RO','5''h10','The Watchdog Timer counter width.'),
    @('[23:20]','WDT_DFLT_TOP_INIT','RO','4''h0',"Describes the initial timeout period that is available directly after reset. It controls the reset value of the register. If WDT_HC_TOP is 1, then the default initial time period is the only possible period."),
    @('[19:16]','WDT_DFLT_TOP','RO','4''h0',"Selects the timeout period that is available directly after reset. It controls the reset value of the register. If WDT_HC_TOP is set to 1, then the default timeout period is the only possible timeout period. Can choose one of 16 values."),
    @('[15:13]','reserved','RO','3''h0',''),
    @('[12:10]','WDT_DFLT_RPL','RO','3''h0','The reset pulse length that is available directly after reset.'),
    @('[9:8]','APB_DATA_WIDTH','RO','2''h2',"Width of the APB Data Bus to which this component is attached.`n`nValues:`n0x0 (APB_8BITS): APB data width is 8 bits`n0x1 (APB_16BITS): APB data width is 16 bits`n0x2 (APB_32BITS): APB data width is 32 bits"),
    @('[7]','WDT_PAUSE','RO','1''h1',"Configures the peripheral to have a pause enable signal (pause) on the interface that can be used to freeze the watchdog counter during pause mode.`n`nValues:`n0x0 (DISABLED): Pause enable signal is non existent`n0x1 (ENABLED): Pause enable signal is included"),
    @('[6]','WDT_USE_FIX_TOP','RO','1''h0',"When this parameter is set to 1, timeout period range is fixed. The range increments by the power of 2 from 2^16 to 2^(WDT_CNT_WIDTH-1). When this parameter is set to 0, the user must define the timeout period range (2^8 to 2^(WDT_CNT_WIDTH)-1) using the WDT_USER_TOP_(i) parameter.`n`nValues:`n0x0 (USERDEFINED): User must define timeout values`n0x1 (PREDEFINED): Use predefined timeout values"),
    @('[5]','WDT_HC_TOP','RO','1''h0',"When set to 1, the selected timeout period(s) is set to be hard coded.`n`nValues:`n0x0 (PROGRAMMABLE): Timeout period is programmable`n0x1 (HARDCODED): Timeout period is hard coded"),
    @('[4]','WDT_HC_RPL','RO','1''h0',"Configures the reset pulse length to be hard coded.`n`nValues:`n0x0 (PROGRAMMABLE): Reset pulse length is programmable`n0x1 (HARDCODED): Reset pulse length is hardcoded"),
    @('[3]','WDT_HC_RMOD','RO','1''h0',"Configures the output response mode to be hard coded.`n`nValues:`n0x0 (PROGRAMMABLE): Output response mode is programmable`n0x1 (HARDCODED): Output response mode is hard coded"),
    @('[2]','WDT_DUAL_TOP','RO','1''h0',"When set to 1, includes a second timeout period that is used for initialization prior to the first kick.`n`nValues:`n0x0 (DISABLED): Second timeout period is not present`n0x1 (ENABLED): Second timeout period is present"),
    @('[1]','WDT_DFLT_RMOD','RO','1''h1',"Describes the output response mode that is available directly after reset. Indicates the output response the WDT gives if a zero count is reached; that is, a system reset if equals 0 and an interrupt followed by a system reset, if equals 1. If WDT_HC_RMOD is 1, then default response mode is the only possible output response mode.`n`nValues:`n0x0 (DISABLED): System reset only`n0x1 (ENABLED): Interrupt and system reset"),
    @('[0]','WDT_ALWAYS_EN','RO','1''h0',"Configures the WDT to be enabled from reset. If this setting is 1, the WDT is always enabled and a write to the WDT_EN field (bit 0) of the Watchdog Timer Control Register (WDT_CR) to disable it has no effect.`n`nValues:`n0x0 (DISABLED): Watchdog timer disabled on reset`n0x1 (ENABLED): Watchdog timer enabled on reset")
  )},
  @{ Offset='0f8h'; Reg='WDT_COMP_VERSION'; Fields= ,@('[31:0]','WDT_COMP_VERSION','RO','32''h3131322a',"ASCII value for each number in the version, followed by *. For example, 32_30_31_2A represents the version 2.01*.")},
  @{ Offset='0fch'; Reg='WDT_COMP_TYPE'; Fields= ,@('[31:0]','WDT_COMP_TYPE','RO','32''h44570120',"Designware Component Type number = 0x44_57_01_20. This assigned unique hex value is constant, and is derived from the two ASCII letters `"DW`" followed by a 16-bit unsigned number.")}
)

Add-Type -AssemblyName System.Drawing
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Add()
$ws = $wb.Worksheets.Item(1)
$ws.Name = 'WWDT_Registers'

# Header
$headers = @('Offset','Register Name','SubBits','Field Name','Attribute','DefaultValue','Description')
for ($c = 0; $c -lt $headers.Count; $c++) {
  $ws.Cells.Item(1, $c + 1) = $headers[$c]
}

# Data rows
$row = 2
foreach ($g in $regs) {
  $startRow = $row
  foreach ($f in $g.Fields) {
    $ws.Cells.Item($row, 1) = $g.Offset
    $ws.Cells.Item($row, 2) = $g.Reg
    $ws.Cells.Item($row, 3) = [string]$f[0]
    $ws.Cells.Item($row, 4) = [string]$f[1]
    $ws.Cells.Item($row, 5) = [string]$f[2]
    $ws.Cells.Item($row, 6) = [string]$f[3]
    $ws.Cells.Item($row, 7) = [string]$f[4]
    $row++
  }
  $endRow = $row - 1
  if ($endRow -gt $startRow) {
    $ws.Range("A${startRow}:A${endRow}").Merge()
    $ws.Range("B${startRow}:B${endRow}").Merge()
  }
}
$lastRow = $row - 1

$used = $ws.Range("A1:G${lastRow}")

# Column widths
$widths = @(8, 20, 10, 24, 10, 14, 100)
for ($c = 0; $c -lt $widths.Count; $c++) {
  $ws.Columns.Item($c + 1).ColumnWidth = $widths[$c]
}

# Alignment & wrap
$used.VerticalAlignment = -4108  # xlCenter
$ws.Range("A1:F${lastRow}").HorizontalAlignment = -4108  # xlCenter
$used.WrapText = $true

# Header style (orange, bold)
$hdr = $ws.Range('A1:G1')
$hdr.Font.Bold = $true
$hdr.Interior.Color = [System.Drawing.ColorTranslator]::ToOle([System.Drawing.Color]::FromArgb(242, 143, 44))

# Offset column light green (like source table)
$offsetCol = $ws.Range("A2:A${lastRow}")
$offsetCol.Interior.Color = [System.Drawing.ColorTranslator]::ToOle([System.Drawing.Color]::FromArgb(146, 208, 80))

# Borders
$used.Borders.LineStyle = 1
$used.Borders.Weight = 2
$used.Borders.Color = 0

# Font
$used.Font.Name = 'Calibri'
$used.Font.Size = 10

# Freeze header row
$ws.Activate()
$excel.ActiveWindow.SplitRow = 1
$excel.ActiveWindow.FreezePanes = $true

# Save as xlsx (51 = xlOpenXMLWorkbook)
$wb.SaveAs($outPath, 51)
$wb.Close($false)
$excel.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ws) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

Write-Output "SAVED: $outPath"
