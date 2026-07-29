# ADS6149 到 FFT 频谱结果：新版 ILA 板测指南

更新日期：2026-07-29  
适用器件：Mizar Z7，`xc7z020clg400-2`，ADC0 直插 ADS6149  
工具版本：Vivado 2020.2

## 1. 当前闭环

新版镜像覆盖：

`ADS6149 200 MSPS -> 异步 FIFO -> /10 -> 20 MSPS -> 255 tap FIR -> /10 -> 2 MSPS -> 4096 点帧 -> Hann -> Xilinx FFT -> 功率谱 -> 最强三峰 -> 基波频率/幅值码/分量数`

FFT 固定为 4096 点、自然顺序、16 bit 定点、块浮点缩放。频率间隔为
`2 MHz/4096 = 488.28125 Hz`。只在 10 kHz--500 kHz，即 bin 21--1024
之间检测局部峰值，最多报告三个分量。

当前频率输出已经使用峰值左右相邻 bin 的 Hann 三点公式估计小数 bin；幅值输出
在相干增益和 FFT 块指数恢复的基础上，按该小数 bin 修正 Hann 栅栏损失。粗略
`peakN_bin` 仍保留整数 bin 便于观察，`fundamental_frequency_hz` 是细化后的结果。
输出幅值仍是 ADC 峰值码，必须经过板级电压校准后才能成为满足 5 mV 指标的 mV 值。

赛题原文的板测硬约束如下：信号源输出阻抗为 50 Ω；测试电缆为 50 Ω、两端
BNC；信号发生器各参数设置值作为测量标称值。因此装置输入按 50 Ω 系统匹配，
信号发生器的负载/匹配阻抗必须设置为 `50 Ω`，不能使用 `High-Z`。任务 1 输入为
100--250 mVpp、10--200 kHz；任务 2 输入为 50--250 mVpp、10--500 kHz；
任务 3 还叠加 200 mVpp、频率不低于 1 MHz 的单音干扰。每项测量不超过 2 s，
幅值、峰峰值和真有效值绝对误差均不超过 5 mV，基频误差不超过 1 kHz。

## 2. 构建产物

- Bitstream：`results/board_ila/g_board_ila.bit`
- Probe：`results/board_ila/g_board_ila.ltx`
- 构建清单：`results/board_ila/build_manifest.txt`
- 重建命令：`powershell -ExecutionPolicy Bypass -File scripts/run_g_board_ila_build.ps1`

本次 SHA-256：

- bit：`498037AD44BBFB687DC9D8B6F603D2EBB6105024A5B5217520CE2946A66D7713`
- ltx：`4C243A9849402660B80AB763CC3DE18904C4849E315753B954DA5D787698BFD0`

最终实现结果：WNS `+0.184 ns`，WHS `+0.034 ns`，TNS/THS 均为 0；
DRC Error/Critical Warning 为 0，CDC Critical 为 0，未约束路径为 0。
资源为 5898 LUT、11420 FF、71 BRAM tile、23 DSP。

仍保留两项板级限制：ADC `CLKOUT` 位于非专用时钟脚 L20，约束沿用原厂例程的
`CLOCK_DEDICATED_ROUTE FALSE`；TI 对 150 MSPS 以上并行 CMOS 更推荐外部同源
时钟捕获，所以 200 MSPS 稳定性仍需多频点、冷热机重复验证。

## 3. ILA 探针

ILA 时钟为 200 MHz，深度 8192，对应 40.96 us。FFT 输出连续 4096 拍，约
20.48 us，因此可以完整抓取一帧频谱。数据仅在对应 valid 为 1 时有意义。

Vivado Hardware Manager 通常显示“信号名”而不是 `probeN`。以下编号严格按照
`g_board_ila_top.v` 和本版 `.ltx` 的连接顺序排列，可以直接逐行对照：

| Probe 编号 | Vivado 中的信号名 | 含义 | 显示格式 | 有效条件 |
|---|---|---|---|---|
| `probe0[13:0]` | `fifo_dout[13:0]` | FIFO 后 ADC 原始二补码 | Signed Decimal/Analog | `probe14[2]`，即 `ila_control[2]` |
| `probe1[15:0]` | `debug_fir_output_data[15:0]` | 20 MSPS FIR 输出 | Signed Decimal/Analog | `probe14[4]`，即 `ila_control[4]` |
| `probe2[15:0]` | `fft_real[15:0]` | Hann 后 FFT 实输入 | Signed Decimal/Analog | `probe14[9]`，即 `ila_control[9]` |
| `probe3[31:0]` | `fft_output_real[15:0]`、`fft_output_imag[15:0]` | FFT 复数输出；低 16 bit 为 real，高 16 bit 为 imag | 两项均设为 Signed Decimal/Analog | `probe13[3]`，即 `ila_spectrum_control[3]` |
| `probe4[32:0]` | `spectrum_power[32:0]` | `real^2+imag^2` 功率 | Unsigned Decimal/Analog | `probe13[5]`，即 `ila_spectrum_control[5]` |
| `probe5[11:0]` | `spectrum_bin[11:0]` | 当前自然顺序 FFT bin | Unsigned Decimal | `probe13[5]`，即 `ila_spectrum_control[5]` |
| `probe6[11:0]` | `peak0_bin[11:0]` | 最强分量所在 FFT bin | Unsigned Decimal | 结果锁存后 |
| `probe7[11:0]` | `peak1_bin[11:0]` | 第二强分量所在 FFT bin | Unsigned Decimal | 结果锁存后 |
| `probe8[11:0]` | `peak2_bin[11:0]` | 第三强分量所在 FFT bin | Unsigned Decimal | 结果锁存后 |
| `probe9[15:0]` | `peak0_amplitude_code[15:0]` | 最强分量 ADC 峰值码 | Unsigned Decimal | 结果锁存后 |
| `probe10[15:0]` | `peak1_amplitude_code[15:0]` | 第二强分量 ADC 峰值码 | Unsigned Decimal | 结果锁存后 |
| `probe11[15:0]` | `peak2_amplitude_code[15:0]` | 第三强分量 ADC 峰值码 | Unsigned Decimal | 结果锁存后 |
| `probe12[19:0]` | `fundamental_frequency_hz[19:0]` | 最低有效分量频率，单位 Hz | Unsigned Decimal | 结果锁存后 |
| `probe13[15:0]` | `ila_spectrum_control[15:0]` | FFT/频谱状态 | Binary/Hex | 始终 |
| `probe14[15:0]` | `ila_control[15:0]` | 原采集/FIR/帧状态 | Binary/Hex | 始终 |
| `probe15[7:0]` | `ila_fifo_status[7:0]` | ADC 异步 FIFO 状态 | Binary/Hex | 始终 |
| `probe16[4:0]` | `fft_error_sticky[4:0]` | FFT 原始事件粘滞位 | Binary | 始终 |

新版 bit/ltx 已把三个 bin 和三个幅值分别接到独立物理探针，因此不需要在
Hardware Manager 中把 36 bit 或 48 bit 打包总线手工切片。`0` 表示最强分量，
`1` 表示第二强，`2` 表示第三强，排序依据是幅值而不是频率。

若审核的是上一版已经保存的 `.ila/.csv`，旧 `ila_peak_amplitudes[47:0]` 仍按
`{amp2,amp1,amp0}` 打包。本次截图的总线十进制值 `67121` 等于十六进制
`0x000000010631`，所以实际为 `amp0=1585`、`amp1=1`、`amp2=0`，并不是单个
幅值达到 67121。由于 `component_count=1`，只有 `amp0` 有效。

`probe13 = ila_spectrum_control`，也就是 Vivado 列表中的
`ila_spectrum_control[15:0]`：

| 位 | 名称 | 正常含义 |
|---:|---|---|
| 0 | `fft_configured` | 复位后稳定为 1 |
| 1 | `fft_input_valid` | Hann 输入有效 |
| 2 | `fft_input_ready` | FFT 可以接收输入 |
| 3 | `fft_output_valid` | `probe3` 有效 |
| 4 | `fft_output_last` | bin 4095 的单拍标志 |
| 5 | `spectrum_valid` | `probe4/5` 有效 |
| 6 | `results_valid` | 三峰、频率和幅值锁存完成的单拍脉冲 |
| 8:7 | `component_count` | 有效分量数 0--3 |
| 13:9 | `block_exponent` | FFT 块浮点右移总位数 |
| 14 | `fft_frame_started` | FFT 接收新帧事件 |
| 15 | `fft_protocol_error` | 必须始终为 0；不包含允许的 Non-Realtime 输入等待 |

`probe16 = fft_error_sticky[4:0]` 的原始事件含义：bit 0 为 TLAST 提前，bit 1
为 TLAST 缺失，bit 2 为状态输出阻塞，bit 3 为 FFT 输入等待，bit 4 为数据输出
阻塞。本设计明确使用 Non-Realtime 模式，输入流在 Hann ROM/乘法流水间存在
合法间隙，所以 bit 3 可能置 1；该模式会暂停而不会破坏 FFT 帧。通过条件是
bit 0/1/2/4 为 0，不能再把 bit 3 单独置 1 判为失败。

`probe14 = ila_control[15:0]`，其位定义保持上一版不变：bit 0/1 为 MMCM/系统复位，bit 2 为 ADC
连续流 valid，bit 3 为 20 MSPS valid，bit 4 为 FIR valid，bit 5 为帧完成，
bit 9/11/12 为 Hann 输入 valid/last/frame done，bit 13--15 为主链错误。
`probe15 = ila_fifo_status[7:0]`，正常稳态仍应为 `0x80`。

## 4. 建议抓取方法

### A. 单音频率、幅值与分量数

以 20 kHz、200 mVpp、50 Ω、零偏置条件为例：

1. 触发设为 `ila_spectrum_control[6] == 1`（即 `probe13[6]`），Trigger Position
   设为 `5734`，约为 8192 深度的 70%。
2. 抓取后在触发点读取稳定结果：
   - `ila_spectrum_control[8:7]`（`probe13[8:7]`）应为 1；
   - `fundamental_frequency_hz`（`probe12`）应接近 20000 Hz；
   - `peak0_bin`（`probe6`）应为 41，对应 20019.5 Hz；
   - `peak0_amplitude_code`（`probe9`）是最强分量 ADC 峰值码；
   - `ila_spectrum_control[15]`、`ila_control[15:13]` 必须为 0，
     `ila_fifo_status` 为 `0x80`。
3. `peak1/peak2` 寄存器可能保留低于门限的噪声局部峰，但只有
   `component_count` 指示的前若干项有效，不能仅因为 bin 非零就认为存在分量。

若要观察完整频谱形状，改用 `ila_spectrum_control[3] == 1`（`probe13[3]`）
触发，Trigger Position 设为 5%--10%。应看到 `spectrum_bin`（`probe5`）从 0
连续递增到 4095；正频率只看 0--2048，测量带只看 21--1024。

### B. Trigger Position 的 GUI 操作与意义

Trigger Position 不是百分比输入框，而是捕获 RAM 中的样本序号。本设计深度为
8192，70% 对应 `round(8192*0.70)=5734`：

1. 在 Hardware Manager 中选中 `hw_ila_1`。
2. 点击截图左侧竖排的 **ILA Core Properties**；也可在 Dashboard 的
   **Capture Mode Settings** 中找到同一设置。
3. 将 **Trigger Position** 填为 `5734`，按 Enter 或 Apply。
4. 确认 Data Depth 为 `8192`，再点击 Run Trigger。

也可以在 Tcl Console 执行：

`set_property CONTROL.TRIGGER_POSITION 5734 [get_hw_ilas hw_ila_1]`

其意义是触发事件落在第 5734 个样本附近：保留约 5734 个触发前样本和 2457 个
触发后样本。用 `results_valid` 触发时，FFT 的 4096 个频谱输出发生在结果脉冲
之前；70% 可以保留完整频谱及前导裕量。本次导出的触发行是 4096，说明当时实际
仍为 50% 位置，因此只抓到了约 4012 个 FFT 有效输出，没有覆盖完整一帧。

### C. 双音/三音叠加

设置两个或三个已知频率，建议相隔至少 6 个 bin，即约 2.93 kHz，并让最弱分量
先不低于最强分量的 10%。通过条件：

- `component_count` 等于实际分量数；
- `peak0/1/2_bin`（`probe6/7/8`）按幅值从强到弱排序，不按频率排序；
- `fundamental_frequency_hz`（`probe12`）输出通过门限的最低频率，因此代表基波候选；
- `peak0/1/2_amplitude_code`（`probe9/10/11`）的比例接近信号源设置比例；
- FFT/主链/FIFO 错误位全部为 0。

当前峰值功率门限为最强峰功率的 `1/2048`，相当于幅度约 2.21%。最弱分量接近
噪声底或相邻频率过近时，分量数只是初筛结果；最终版本还需要结合噪声底、谐波
关系和最小二乘拟合。

不需要把多台信号源直接并接到 ADC。按优先级使用以下方法：

1. 优先使用信号发生器的 **Harmonic Generator/谐波发生** 功能。它会从同一个
   BNC 端口直接输出基波与谐波之和，最符合赛题给出的测试方式，不需要外置加法器。
2. 若信号源有 ARB/任意波功能，在 PC 上生成
   `u(t)=A1*sin(2*pi*f1*t)+A2*sin(2*pi*2*f1*t+phi2)+A3*sin(2*pi*3*f1*t+phi3)`，
   将 CSV/ARB 波形导入信号源。信号源输出负载仍设为 `50 Ω`，并检查合成波的总
   峰峰值没有超出赛题范围和 ADC 输入范围。
3. 若只有双通道正弦输出，可制作三端口 50 Ω 电阻合路器：CH1、CH2、ADC 三个
   端口各通过一个 `16.9 Ω/1%` 电阻连接到公共点。每个分量到 ADC 约衰减 6 dB，
   因而信号源设置值约为目标端口值的两倍，并应由示波器复核。严禁用 BNC-T 将
   两个信号源输出直接硬并联，否则两个低阻输出会互相驱动。

若现有信号源既无谐波/ARB、也不能做电阻合路，则暂时无法完成真实模拟多音板测。
此时先以 XSim/MATLAB 三音向量验证数字算法，以 10--500 kHz 单音扫频验证 ADC、
抽取、FIR 和 FFT 硬件链路；取得谐波/ARB 信号源或合路器后再补最终多音验收。

### D. 幅值校准

`peak0/1/2_amplitude_code`（`probe9/10/11`）是 ADC code，不直接等于 mV。
现场建议提供
“零点校准 + 增益校准”：

1. 输入端接规定终端并关闭信号，测量原始均值作为零偏；
2. 输入一个经过示波器在 ADC 接口处确认的已知正弦，例如 100 kHz；
3. 记录已知 `Vpp_cal_mV` 和 `amp0_code`；
4. 计算 `gain_mV_per_code = Vpp_cal_mV/(2*amp0_code)`；
5. 屏幕显示使用 `Vpeak_mV = amp_code*gain_mV_per_code`，再计算各分量、Upp 和
   Urms。建议至少用低、中、高三个幅值点检查线性度。

本题统一使用 50 Ω 系统：信号发生器负载设置 `50 Ω`、50 Ω BNC 电缆、装置端
50 Ω 匹配。若误设为 High-Z，信号源设置值与装置端实际 Vpp 可能相差约一倍。
绝对幅值校准除记录信号源标称值外，仍建议以 ADC 模块 BNC 端示波器实测值复核。

#### D.1 固定点换算

频谱模块输出的是每个正弦分量的峰值码 `Acode`。若校准参考输入为
`Vpp_cal_mV`，则单点增益为：

`K_mV_per_code = Vpp_cal_mV/(2*Acode_cal)`

FPGA/串口显示建议保存为 Q12.20：

`K_q20 = round(K_mV_per_code*2^20)`

运行时只需要整数乘法：

- `Vpeak_mV = (Acode*K_q20 + 2^19) >> 20`
- `Vpp_component_mV = 2*Vpeak_mV`
- 单个正弦 `Vrms_mV = Vpeak_mV/sqrt(2)`
- 多个互为谐波的分量若不含直流，
  `Vrms_total = sqrt((Vpeak1^2+Vpeak2^2+Vpeak3^2)/2)`

ADC 原始时域波形还需要零偏码 `C0`：

`sample_mV = (sample_code-C0)*K_mV_per_code`

频谱分量幅值本身来自交流 bin，正常情况下不应再减 `C0`；`C0` 用于波形纵轴、
直流量和直接时域统计。

#### D.2 推荐校准流程

1. 信号源关闭，ADC 输入保持规定的 50 Ω 终端，连续平均至少 4096 个原始样本，
   得到零偏码 `C0`。
2. 固定为 `50 Ω`、零直流偏置，输入一个已知正弦；优先用示波器在 ADC BNC 端
   复核实际 Vpp。
3. 每个测试点平均 8--16 帧 `peak0_amplitude_code`，抑制随机抖动。
4. 在 50/100/150/200/250 mVpp 做线性度；用最小二乘拟合
   `Vpeak_mV=K*Acode+B`。若 `B` 很小，最终强制过原点只保存 `K`；若 `B` 明显，
   先排查噪声门限、源输出和 ADC 前端，不要直接用非零截距掩盖硬件问题。
5. 在 10/20/50/100/200/300/400/500 kHz 重复一个中等幅值点，形成频响校准表
   `K(f)`；相邻频点线性插值。数字 FIR 通带很平，表中变化主要补偿模拟前端、
   变压器、ADC 和接线的实际频响。
6. 校准常数应带版本号和 CRC，存入非易失介质；在 QSPI/EEPROM/PS 软件尚未接入
   前，可由串口屏在开机后重新下发到 FPGA 寄存器。

串口屏建议提供两个受保护按钮：`零点校准` 只更新 `C0`；`增益校准` 要求用户输入
当前信号源的 Vpp，装置自动平均若干帧并计算 `K_q20`。正式测量界面只读取已生效
的校准表，不应在未知输入上自动改写增益。

旧捕获中 `amp0=1585` 的结果来自此前负载条件，不再作为 50 Ω 校准基准。最新
50 Ω 板测得到：20 kHz、200 mVpp 时 `peak0_bin=41`、
`peak0_amplitude_code=3168`、`fundamental_frequency_hz=20020`；因此当前单点
暂定换算为 `200 mVpp/(2*3168)=0.0315657 mV/code`。旧值与新值约差一倍，正是
信号发生器 High-Z/50 Ω 显示模式容易造成的量级差异，后续必须全部固定为 50 Ω
并用 50/100/150/200/250 mVpp 多点测试后再固化到串口屏。

旧版镜像的 300 kHz、400 mVpp 调试点得到 `peak0_bin=614`、
`peak0_amplitude_code=5695`、`fundamental_frequency_hz=299805`。若仅按输入幅值
翻倍，线性预期为 `2*3168=6336`，实测比值为 `5695/6336=0.8988`，即
`-0.93 dB`。这不是 FIR 通带衰减：固定 FIR 在 300 kHz 的理论增益约为
`+0.0004 dB`。主要原因是当前幅值估计器只读取 Hann 窗后的最大单个 FFT bin：
20 kHz 距 bin 41 中心仅 `-19.53 Hz`，而 300 kHz 距 bin 614 中心
`+195.31 Hz=0.4 bin`；Hann 窗在 0.4 bin 偏移处的理论幅值约为 0.9008
（`-0.91 dB`），与板测完全吻合。

新版 RTL 已加入 Hann 三点小数-bin 估计和定点幅值修正。XSim 中 300 kHz
（相对 bin 614 偏移 0.4 bin）的 900-code 输入已恢复为 900 code；10 kHz 已从
错误的约 16.7 kHz 修正为 10.000 kHz。板上重新下载新版 bit 后，应在相同
20 kHz/300 kHz 条件复测，不能继续沿用旧镜像的 `3168/5695` 比值作为校准常数。

建议下一轮单音板测顺序：

1. `10.000000 kHz / 200 mVpp / 50 Ω`，应报告约 10.000 kHz，粗 bin 为 20；
2. `13.000000 kHz / 200 mVpp / 50 Ω`，应报告约 13.000 kHz，粗 bin 为 27；
3. `20.01953125 kHz / 200 mVpp / 50 Ω`，验证 bin 41 中心；
4. `299.8046875 kHz` 与 `300.000000 kHz` 使用相同 Vpp，修正后幅值码应接近；
5. 做 50/100/150/200/250 mVpp 线性度，再做 10--500 kHz 任意频率扫频。

## 5. 仿真与导出

FFT 自检：

`powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1`

测试包含 500 kHz、三音、10 kHz、13 kHz 和 300 kHz 共五帧，自动检查 20480
个 FFT 输出、频点顺序、TLAST、块指数、低频边界、小数-bin 频率、三个幅值和
分量数。查看波形时运行：

`powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1 -Gui`

ILA 审核请同时导出 `.csv` 和 `.ila`，文件名记录信号源频率、Vpp、负载模式、
偏置和触发条件。CSV 用于数值复核，ILA 文件用于在 Vivado 中恢复抓取。
