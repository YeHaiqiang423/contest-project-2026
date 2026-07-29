# ADS6149 到 Hann 输入流：ILA 初步板测指南

更新日期：2026-07-29  
适用器件：Mizar Z7，`xc7z020clg400-2`，ADC0 直插 ADS6149 模块  
Vivado：2020.2

## 1. 本镜像能验证什么

本镜像用于验证当前已经实现的整条数字输入链：

`ADS6149 14 bit/200 MSPS -> IOB 采集 -> 异步 FIFO -> /10 -> 20 MSPS -> 255 tap FIR -> /10 -> 2 MSPS -> 双 4096 点帧 -> Hann 窗 -> FFT ready/valid 输入`

当前还没有实例化 FFT 运算核、峰值检测、参数估计和串口屏。因此 `fft_real` 是加窗后的 FFT 输入，不是频谱输出。没有模拟前置抗混叠滤波器时，也不能用本测试宣称“任意 1 MHz 以上干扰均已抑制”。

## 2. 产物与构建结论

- Bitstream：`results/board_ila/g_board_ila.bit`
- Probe 文件：`results/board_ila/g_board_ila.ltx`
- 构建清单：`results/board_ila/build_manifest.txt`
- 完整报告：`results/board_ila/*_route.rpt`
- 可重复构建：`powershell -ExecutionPolicy Bypass -File scripts/run_g_board_ila_build.ps1`

本次产物 SHA-256：

- `g_board_ila.bit`：`78B85F7F7855B99DBE76A1A1F4C977640BA523DC53787C1E46AA5FF6D1FD75B2`
- `g_board_ila.ltx`：`A01788C2331A6E7C19153FD7A431960C063A8B812BD17338A77CF6B83D111C06`

实现门禁结果：

- 50 MHz 板载时钟，MMCM 输出/系统时钟 200 MHz。
- ADC 数据、返回时钟：`HSTL_II_18`；Bank 35：`INTERNAL_VREF=0.9 V`。
- WNS `+0.217 ns`，WHS `+0.034 ns`，TNS/THS 均为 0。
- 未约束内部端点 0，DRC Error 0，DRC Critical Warning 0。
- CDC Critical 0；剩余一个 CDC-6 Warning 是 5 个彼此独立的只读状态位通过 XPM 数组同步，不参与数据或控制决策。
- 资源：3663 LUT、7458 FF、81.5 BRAM tile、18 DSP。
- 数字端到端 XSim 回归：`640 ADC codes produced 16 verified FFT inputs`，PASS。

两项必须保留的硬件风险：

1. 原厂转接板把 ADC `CLKOUT` 接到 L20 非专用时钟引脚，约束中按原厂例程使用了 `CLOCK_DEDICATED_ROUTE FALSE`。该返回时钟只用于 IOB 采集和异步 FIFO 写端。
2. TI 数据手册明确指出：并行 CMOS 在 `Fs > 150 MSPS` 时推荐使用外部时钟采集，不推荐使用器件 `CLKOUT`。当前 200 MSPS `CLKOUT` 方案是为了与现有直插硬件和原厂例程一致的初测方案，必须靠下面的板测确认；它不是最终时序裕量证明。

## 3. ILA 探针中文解释

所有探针由 200 MHz 系统时钟采样，ILA 深度 32768，对应普通连续抓取时长 `32768 / 200 MHz = 163.84 us`。数据探针在各自 valid 为 0 时只是保持旧值，不能把保持段当成新采样。

| ILA 名称 | RTL 信号 | 中文含义 | 显示建议 | 何时有效 |
|---|---|---|---|---|
| `probe0[13:0]` | `fifo_dout` | ADC 原始码，经异步 FIFO 到系统域 | Signed Decimal + Analog | `probe4[2]=1` |
| `probe1[13:0]` | `debug_adc_sample_data` | 第一层 /10 后的 20 MSPS 样本 | Signed Decimal + Analog | `probe4[3]=1` |
| `probe2[15:0]` | `debug_fir_output_data` | 255 tap FIR 输出 | Signed Decimal + Analog | `probe4[4]=1` |
| `probe3[15:0]` | `fft_real` | 4096 点帧乘 Hann 窗后的实部 | Signed Decimal + Analog | `probe4[9]=1` |
| `probe4[15:0]` | `ila_control` | 主链路有效、帧和错误状态 | Binary/Hex | 始终观察 |
| `probe5[7:0]` | `ila_fifo_status` | ADC 异步 FIFO 状态 | Binary/Hex | 始终观察 |

`probe4 = ila_control` 位定义：

| 位 | 名称 | 正常含义 |
|---:|---|---|
| 0 | `mmcm_locked` | 应稳定为 1 |
| 1 | `system_rst_n` | 复位释放后应稳定为 1 |
| 2 | `adc_stream_valid` | FIFO 预充后应连续为 1；出现空洞需排查采集时钟/FIFO |
| 3 | `adc_sample_valid` | 每 10 个有效原始样本脉冲一次，即 20 MSPS |
| 4 | `fir_output_valid` | FIR 输出有效，稳态应为 20 MSPS |
| 5 | `frame_ready` | 每收满 4096 个 2 MSPS 样本脉冲一次，周期约 2.048 ms |
| 6 | `frame_bank` | 刚完成的帧 Bank，正常时 0/1 交替 |
| 8:7 | `bank_pending` | 等待处理的两个 Bank 状态 |
| 9 | `fft_valid` | `probe3` 有效；本设计约每 5 个系统时钟出现一个样本 |
| 10 | `fifo_read_started` | FIFO 预充达到 16 字后应稳定为 1；用于确认读启动门已经打开 |
| 11 | `fft_last` | 第 4096 个加窗样本，应与 `fft_valid` 同时为 1 |
| 12 | `frame_done` | 一帧 Hann 输出完成并释放 Bank 的单周期脉冲 |
| 13 | `adc_input_overrun` | 必须始终为 0；置 1 后保持到复位 |
| 14 | `frame_overrun` | 必须始终为 0；置 1 后保持到复位 |
| 15 | `scheduler_overrun` | 必须始终为 0；置 1 后保持到复位 |

`probe5 = ila_fifo_status` 位定义：

| 位 | 名称 | 稳态期望 |
|---:|---|---|
| 0 | `empty` | 0 |
| 1 | `full` | 0 |
| 2 | `overflow_pulse` | 0；窄脉冲可能被系统域采样漏掉，以 bit 3 为准 |
| 3 | `overflow_sticky` | 必须为 0；置 1 后需要复位清除 |
| 4 | `underflow` | 0 |
| 5 | `wr_rst_busy` | 启动后为 0 |
| 6 | `rd_rst_busy` | 启动后为 0 |
| 7 | `adc_return_rst_n` | ADC 返回时钟存在并释放复位后为 1 |

## 4. 上电和 Hardware Manager 操作

1. 断电状态下确认 ADC 模块插接方向、ADC0 接口、地和电源。信号源先关闭输出。不要热插拔模块或同轴线。
2. 连接 JTAG，给板卡和 ADC 模块按硬件说明供电。你已测得 ADC 与 FPGA 电平匹配；本镜像仍按原厂 XDC 使用 `HSTL_II_18`，不是 `LVCMOS33` 数据输入。
3. Vivado 2020.2 中打开 `Hardware Manager -> Open target -> Auto Connect`。
4. 右击 `xc7z020_1 -> Program Device`：
   - Bitstream 选 `G:/workspace/26DianSai/contest-project/results/board_ila/g_board_ila.bit`。
   - Debug probes 选 `G:/workspace/26DianSai/contest-project/results/board_ila/g_board_ila.ltx`。
5. 编程后应看到一个 `hw_ila_1`/`initial_validation_ila`。若显示 probe 不匹配，重新指定同目录的 `.ltx`，不要混用旧 bit 和新 ltx。
6. 把 `probe0` 至 `probe3` 的 Radix 设为 `Signed Decimal`，Waveform Style 设为 `Analog`；`probe4/5` 保持 Binary 或 Hex，并展开所需 bit。
7. 普通抓取使用 1 window、32768 depth、trigger position 约 10%。按一下 B19 复位键再释放，可以清除所有 sticky 错误位并重新开始 FIFO 预充。

也可以在工程根目录用下面命令自动连接唯一一片 `xc7z020`、加载同一套 bit/ltx，并停留在 GUI 中；若同时连接了多片器件，脚本会拒绝猜测目标：

`D:\XUni\Vivado\2020.2\bin\vivado.bat -mode gui -source scripts/program_g_board_ila_hw.tcl`

## 5. 分阶段测试

### A. 无信号健康检查

ADC 输入按模块要求接 50 ohm 终端，或者保持信号源连接但输出关闭。立即触发一次。

通过条件：

- `control[0]=1`、`control[1]=1`、`control[10]=1`、`fifo_status[7]=1`。
- 启动完成后 `control[2]` 连续为 1。
- `fifo_status[3:1]=000`、`fifo_status[6:4]=000`。
- `control[15:13]=000`。
- 原始码只在一个小噪声带内波动，不固定在 `0x0000`/`0x3fff`，也不出现大范围随机跳码。

若 `control[0]=0`：检查 H16 50 MHz 板钟和 B19 复位。  
若 `fifo_status[7]=0`：检查 L19 是否输出 200 MHz、ADC 是否工作以及 L20 是否返回 CLKOUT。  
若 `control[10]=0`：FIFO 尚未达到预充水位，不能进入后续测试。  
若 `control[2]` 周期性掉 0：先停止后续算法测试，优先处理 200 MSPS 捕获/FIFO 时序。

### B. 码制、极性和原始 200 MSPS

1. 信号源设为正弦波 `100 kHz`，先设 `100 mVpp`，DC offset 为 0，输出端按实际 50 ohm 负载标定幅度。
2. 确认 ADC 模块输入耦合和允许幅度后再打开输出。不要直接以 ADS6149 芯片的差分满量程推算 SMA 单端允许幅度；板上变压器/驱动增益尚未完成校准。
3. 立即触发，观察 `probe0`，只在 `control[2]=1` 的点上判断。

通过条件：

- 100 kHz 每周期约有 `200 MHz / 100 kHz = 2000` 个原始样本。
- 波形连续、上下半周对称、无单 bit 式毛刺、无固定码和削顶平台。
- 当前 RTL 参数是 `ADC_OFFSET_BINARY=0`，按二进制补码解释。若模拟零点附近原始码约为 `0x2000`，且 Signed Decimal 显示在中点发生 `+8191 -> -8192` 跳变，则硬件实际是 offset binary；这时停止幅值测试，把参数改为 1 后重建，而不是把跳变当作噪声。

建议在确认安全后依次试 `200 mVpp`、`500 mVpp`，每一级记录原始码 min/max。任何一级接近 `-8192/+8191` 或出现平顶就退回上一级。

### C. /10 和 FIR 数据率闭环

保持 `100 kHz` 输入，触发条件设为 `probe4[3] == 1`。

通过条件：

- `control[3]` 相邻脉冲间隔为 10 个 ILA 时钟，即 50 ns，等效 20 MSPS。
- `probe1` 每个有效点构成 100 kHz 正弦，每周期约 200 个有效样本。
- `control[4]` 稳态输出率也是 20 MSPS，`control[13]` 始终为 0。
- FIR 的 255 tap 群延迟为 `(255-1)/2 = 127` 个 20 MSPS 样本，即约 `6.35 us`；比较 `probe1` 与 `probe2` 时必须补偿该延迟并忽略复位后的滤波器填充段。

FIR 设计参数是 20 MSPS、255 tap、750 kHz 截止、Q1.17 系数；模型结果为 0--500 kHz 通带纹波约 0.00195 dB，500 kHz 增益约 -0.00101 dB，1 MHz 起的理论最差阻带约 -76.7 dB。

扫频建议：`100 kHz -> 300 kHz -> 500 kHz -> 750 kHz -> 1 MHz`。每个频点保持输入幅度不变，等滤波器稳定后比较 `probe1` 与 `probe2` 有效样本的峰峰值/RMS：

- 100/300/500 kHz 应基本等幅；板测初步判据可先用幅比误差小于 1%。
- 750 kHz 位于过渡带，不作平坦度验收点。
- 1 MHz 应显著衰减，但 ADC 噪声和 14 bit 动态范围会限制可测阻带深度，不能要求实测一定达到 -76.7 dB。

### D. 4096 点双 Bank 成帧

由于单次连续抓取只有 163.84 us，而帧周期约 2.048 ms，使用 `probe4[5] == 1` 作为触发条件，trigger position 设为约 5%--10%。

通过条件：

- 每次触发时 `frame_ready` 仅高一个时钟。
- 多次重复触发时 `frame_bank` 应 0/1 交替。
- `bank_pending` 可以短暂置位，处理完成后相应位清零。
- `frame_overrun` 和 `scheduler_overrun` 始终为 0。

### E. Hann 窗和 FFT 输入接口

仍以 `probe4[5] == 1` 触发。一次 4096 点输出约每 5 个 200 MHz 时钟产生一个有效样本，总时间约 `4096 * 5 / 200 MHz = 102.4 us`，能够完整落在 163.84 us 的 ILA 窗口中。

通过条件：

- 只在 `control[9]=1` 时读取 `probe3`；有效样本总数应为 4096。
- `fft_last` 只在第 4096 个有效样本上出现一次，并与 `fft_valid` 同时为 1。
- 随后出现一次 `frame_done`，Bank 被释放。
- `probe3` 的包络在帧首尾接近 0，在帧中部最大，虚部在 RTL 中固定为 0。
- `control[15:13]` 和 `fifo_status[3]` 全程为 0。

## 6. 200 MSPS 捕获可靠性专项

这是本轮最重要的硬件结论，不能只测一个低频正弦。建议保持不削顶的固定幅度，依次测试：

- 输入频率：100 kHz、500 kHz、1 MHz、5 MHz、9 MHz。
- 每个频点重复抓取至少 20 次；冷热机各做一轮更好。
- 观察 `probe0` 是否有偶发大跳码、重复/漏样式相位突变，以及 `control[2]` 是否出现空洞。
- 全程检查 `fifo_status[3]` 和 `control[15:13]` 是否曾置 1；sticky 位一旦置 1，即使后来恢复也判失败。

说明：5 MHz 和 9 MHz 仅用于检查 ADC 数字接口连续性，不是当前 0--500 kHz 测量通带验收。由于尚无模拟抗混叠滤波器，10 MHz 以上信号在第一层 `/10` 前可能混叠进 0--10 MHz；例如接近 20 MHz 的干扰可能在 20 MSPS 域落到低频，之后的 FIR 无法辨别其来源。

若低频稳定但高频频繁跳码，优先方向不是修改 FIR，而是把 ADC 数据采集改成由外部 200 MHz 同源时钟经 MMCM 相移/IDELAY 校准的 IOB 采集，并扫相位寻找数据眼中心；这正是 TI 对 150 MSPS 以上 CMOS 模式的建议方向。

## 7. 结果记录模板

每个测试频点至少记录：

| 项目 | 记录值 |
|---|---|
| bit/ltx SHA-256 是否匹配 |  |
| 输入频率、源端幅度、50 ohm 实测幅度 |  |
| `probe0` min/max、是否削顶/跳码 |  |
| `control[2]` 是否连续 |  |
| `probe1` 有效周期是否符合 20 MSPS |  |
| `probe2/probe1` 幅比 |  |
| `frame_bank` 是否交替 |  |
| Hann 有效样本数、`fft_last` 次数 |  |
| `fifo_status[3]` |  |
| `control[15:13]` |  |
| ILA 截图或导出 CSV 文件名 |  |

只要任一 sticky 错误位置 1、`control[2]` 稳态不连续、码制判断不一致，或者高频专项出现不可重复跳码，就不要进入 FFT 核与幅值标定阶段；先解决 ADC 捕获链。
