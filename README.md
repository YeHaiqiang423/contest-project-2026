# 电赛 FPGA 项目

本仓库用于电赛期间的 MATLAB 算法建模、定点化、RTL 实现、XSim 仿真、Vivado 综合实现和板级验证。

## 当前硬件

- 开发板：MicroPhase Mizar Z7，Zynq-7000 SoC
- 目标器件：`xc7z020clg400-2`（以最终所用板卡丝印和工程设置为准）
- PL 板载时钟：50 MHz，约束信号名 `PL_CLK_50M`；资料中的通用 XDC 也包含 `clk`/H16，使用前必须按顶层端口复核
- ADC：Texas Instruments ADS6149（实物丝印已确认；本地数据手册覆盖 ADS6149/ADS6148 系列）
- DAC：Texas Instruments DAC5688
- DAC 配置参考：STM32F103 + HAL/SPI/USB CDC 例程

硬件手册、原理图、尺寸图、芯片数据手册和厂商参考工程保存在本地 `docs/`。该目录体积较大且含厂商资料，不纳入 Git。

## 参考资料注意事项

- `docs/02_Mizar Z7硬件资料/` 包含 Mizar Z7 Rev.1.1 用户手册、原理图和 `Mizar_Z7_7Z020.xdc`。
- `docs/高性能ADC_DAC模块资料/` 包含 ADS6148/DAC5688 数据手册、硬件设计、DAC 配置例程和 FPGA 回环工程。
- FPGA 回环参考工程目标器件为 `xc7z020clg400-2`，但工程由 Vivado 2025.2 生成；本机使用 Vivado 2020.2。不要直接用 2020.2 覆盖或降级原工程，应从参考工程提取 RTL、XDC 和 IP 参数，在本项目中新建兼容工程并重新生成 IP。
- 厂商 XDC 只能作为引脚来源，启用约束前必须核对板卡型号、顶层端口、电压和时钟频率。

## 目录

- `docs/`：本地硬件资料与厂商例程，不提交 Git
- `matlab/model/`：浮点黄金模型
- `matlab/fixed/`：定点化模型
- `matlab/vectors/`：输入向量与黄金输出
- `rtl/src/`：Verilog/SystemVerilog 可综合源码
- `rtl/tb/`：自检 Testbench
- `rtl/constraints/`：XDC、引脚和时钟约束
- `scripts/`：仿真、综合和结果比对脚本
- `logs/`：仿真、综合和时序日志
- `results/`：波形、报告和测试结果

## VS Code、MATLAB 与 Vivado 共用源码

1. 用 VS Code 打开本目录：`code G:\workspace\26DianSai\contest-project`。
2. 安装官方扩展 `MathWorks.language-matlab`。项目设置已把 `MATLAB.installPath` 指向 `G:\Matlab`，并设为按需启动，避免打开 `.m` 文件时立即占用大量内存。
3. 在 Vivado 中新建 2020.2 工程，把 `rtl/src/`、`rtl/tb/` 和 `rtl/constraints/` 中的文件以引用方式加入工程；不要选择复制源文件到工程目录。
4. 日常编辑统一在 VS Code 完成。MATLAB 扩展负责运行和调试 `.m` 文件；Vivado/XSim 负责 HDL 仿真、综合、实现与下载。三者看到的是磁盘上的同一份文件。
5. 不要同时在 VS Code、MATLAB Editor 和 Vivado Text Editor 中修改同一文件，以免最后保存的一方覆盖另一方。

VS Code 已安装 Verilog HDL、TerosHDL 和 WaveTrace 等扩展；项目还会推荐 MathWorks 官方 MATLAB 扩展。

## 本机工具

- MATLAB R2024b (24.2)：`G:\Matlab`
- Vivado/XSim 2020.2：`D:\XUni\Vivado\2020.2`
- Git 2.47.1：`D:\Git`

## 最小闭环示例：饱和增益

示例实现 `y = saturate_int16(3*x)`，用于验证 MATLAB -> 文本向量 -> RTL/Testbench -> XSim -> Vivado 综合的完整链路，不依赖任何 IP。

在项目根目录依次运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_matlab_vectors.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_synth.ps1
```

- MATLAB 生成 `matlab/vectors/sat_gain_input.txt` 和 `sat_gain_expected.txt`。
- Testbench 自动读取并逐项比对，成功时输出 `PASS`。
- 综合目标为 `xc7z020clg400-2`，仅执行综合，不做实现或 bitstream。
- 日志写入 `logs/`，综合报告写入 `results/synth_sat_gain/`；它们默认不提交 Git。

## GitHub

计划托管到 [YeHaiqiang423](https://github.com/YeHaiqiang423) 账户。创建远程仓库前先确认仓库名称和可见性；`docs/` 已由 `.gitignore` 整体排除。

## 赛题目标与已确认硬件

本仓库面向 2026 年 G 题“周期信号测量分析装置”。输入由基波和一至两个
谐波组成，每项测量须在 2 s 内完成，并显示一或三个完整周期、峰峰值、真有效值、
基波频率、定性频谱和各分量峰值幅度。电压/幅度绝对误差限为 5 mV，基波频率
误差限为 1 kHz，频率分辨率要求 500 Hz。

- 任务 1：100--250 mVpp，各分量 10--200 kHz。
- 任务 2：50--250 mVpp，各分量 10--500 kHz。
- 任务 3：任务 2 信号叠加 200 mVpp、1 MHz 及以上单音干扰，显示结果仍应描述
  有用信号。

赛题明确规定信号源输出阻抗和测试电缆特性阻抗均为 50 Ω，电缆两端为 BNC；
本装置输入端按 50 Ω 系统进行匹配，板测时信号发生器的负载/匹配阻抗设置必须选
`50 Ω`，不能选 `High-Z`。题目以信号发生器各参数设置值作为测量标称值。

已确认 ADC 实物为 ADS6149（14 bit，按 200 MSPS 使用）；ADC 接口相关 FPGA
I/O 供电为 3.3 V，且板级电压匹配已经实测。系统只需使用一路 ADC。显示采用
陶晶驰串口屏，因此 HDMI 不在设计范围内；串口屏具体型号、波特率和 FPGA 引脚
待接线确定后再固化。ADC 数据脚仍应按 ADC 实际输出模式和参考设计选取 I/O
标准，Bank 为 3.3 V 并不等于这些数据脚应直接约束为 `LVCMOS33`。

## 测量架构

```text
BNC/50 ohm -> 模拟抗混叠/抑制干扰低通 -> ADA4937 -> ADS6149
           -> 200 MSPS 采集 -> /10 -> 20 MSPS 数字低通
           -> 波形/Upp/RMS 分支
           -> /10 -> 2 MSPS、4096 点频谱分析
           -> UART 数值与波形数据包
```

2 MSPS 下 4096 点变换的频率间隔为 488.28125 Hz。当前板级 RTL 用 Hann 三点
插值估计亚 bin 频率和恢复峰值幅度；正弦/余弦最小二乘拟合是后续可选的进一步
精修手段，不是当前 ILA 结果的来源。`Urms` 根据谐波幅度计算，`Upp` 在稠密重建
的一个基波周期上求取。任务 3 必须同时依赖模拟和数字滤波：
模拟低通应通过 500 kHz，并从 1 MHz 起提供足够衰减，避免任意高频干扰在首次
抽取时混叠进有用带宽。当前数字模型明确假设此前端条件成立。

运行浮点黄金模型回归：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_model_regression.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fixed_fir_analysis.ps1
```

回归会生成确定性的三项任务波形，模拟 14 bit/2 Vpp ADC 量化，逐项检查题目
数值误差门槛，并把 CSV 与日志分别写入 `results/` 和 `logs/`。

首个正式 RTL 为 `rtl/src/adc_sample_frontend.v`，负责 ADS6149 二补码/偏移二进制
归一化和 200→20 MSPS 抽取。`rtl/src/g_symmetric_fir.v` 是 255 tap、Q1.17、
13 路时分乘法的 20 MSPS 数字低通。运行共享向量、自检仿真和 200 MHz 综合检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_matlab_vectors.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_adc_frontend_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_adc_frontend_synth.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fir_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fir_synth.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_frame_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_frame_synth.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_input_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_input_synth.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_synth.ps1
```

整条“MATLAB 向量→位真 XSim→200 MHz 综合时序”可用一条命令复核：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_closed_loop.ps1
```

当前正式参数集成结果为 1967 LUT、4255 FF、5 BRAM、18 DSP；5 ns 约束下
WNS +1.002 ns、TNS 0。该结果是无板级 XDC 的纯 RTL 综合结果，不代表已经满足
ADC 输入时序或可以生成 bitstream。

板级频谱闭环现已加入 Vivado FFT v9.1：4096 点、自然顺序、16 bit 定点块浮点，
并实现 10--500 kHz 三峰搜索、Hann 三点小数-bin 频率估计，以及栅栏损失/块指数
补偿后的 ADC 幅值码。10 kHz 下边界和 0.4-bin 幅值衰减已有自动回归覆盖。

### Hann 加窗后如何恢复幅值

“FFT 无衰减加窗”不是指存在一种既抑制泄漏、又完全不改变幅值的窗。Hann 窗
必然带来两种确定性损失：约 0.5 的相干增益，以及信号不落在整数 bin 中心时的
栅栏损失。本工程先加窗降低频谱泄漏，再在 FFT 后把这两种损失分别补回来，因而
最终输出接近加窗前的正弦峰值 ADC code。

4096 点对称 Hann 窗定义为：

```text
w[n] = 0.5 - 0.5*cos(2*pi*n/(N-1)),  n = 0...N-1, N = 4096
```

MATLAB 把 `w[n]` 量化为 Q1.15：`round(w[n]*32767)`。由于窗左右对称，FPGA
只在 BRAM 中保存前 2048 个系数，后半窗通过地址镜像读取。每个 16 bit 样本与
16 bit 窗系数相乘，经对称舍入右移 15 bit 后送入 FFT：

```text
xw[n] = round(x[n] * w_q15[n] / 2^15)
```

对实正弦峰值 `A`，若频率恰好落在 bin 中心，则单边 FFT 峰值幅度近似为：

```text
Mcenter ~= A * N * CG / 2 * 2^(-B)
CG = sum(w[n])/N ~= 0.499878
```

其中 `B` 是 Vivado FFT 块浮点输出的 `block_exponent`。本窗满足
`N*CG/2 = 1023.75`，非常接近 `2^10=1024`，所以 RTL 用以下移位恢复 ADC
峰值码：

```text
Acenter ~= Mcenter * 2^(B-10)
```

`g_hann_amplitude_scaler.v` 每拍只移动一位，以避免在 200 MHz 路径上生成可变
桶形移位器。用 1024 近似 1023.75 只产生约 0.0244% 的固定比例误差；最终的
模拟前端增益、ADC 满量程和该微小残差统一由电压校准系数吸收。

仅补相干增益仍不够。频率偏离 bin 中心时，Hann 主瓣能量会分散到相邻点。例如
300 kHz 在本系统中位于 bin 614.4；只读取 bin 614 会保留约 0.9008 的幅值，
即约 `-0.91 dB`。RTL 因此保存峰值左、中、右三个功率，先计算幅度：

```text
L = sqrt(P[k-1]), C = sqrt(P[k]), R = sqrt(P[k+1])
```

然后用同一组三点估算峰值相对整数 bin 的偏移 `delta`：

```text
delta = 2*(R-L)/(L+2*C+R),  -0.5 <= delta <= 0.5
```

`delta` 使用 signed Q1.15。针对本项目的 4096 点对称 Hann 窗，离线拟合得到
栅栏损失倒数的偶次多项式：

```text
Hcorr(delta) ~= 1 + 0.64744225*delta^2 + 0.25902453*delta^4
```

RTL 将两个系数量化为 Q16 的 `42431` 和 `16975`，先计算
`Ccorrected=C*Hcorr(delta)`，再执行块指数/相干增益恢复。该多项式在
`delta=-0.5...+0.5` 范围内对本窗的拟合最坏误差低于约 0.03%；它补偿的是
FFT 栅栏损失，不代替整机的 mV/code 标定和模拟频响校准。

因此幅值路径可以概括为：

```text
ADC code -> Q15 Hann -> block-floating FFT -> |X[k-1:k+1]|
         -> 三点栅栏损失修正 -> 还原 block exponent
         -> 补偿 Hann 相干增益 -> 正弦峰值 amplitude_code
```

### 亚 bin 频率为什么能精确到整数 Hz

整数 FFT bin 只负责粗定位。2 MSPS、4096 点条件下：

```text
delta_f = Fs/N = 2,000,000/4096 = 488.28125 Hz
f_bin(k) = k*488.28125 Hz
```

例如 50 kHz 位于 bin 102.4。频谱搜索先找到整数峰 `k=102`，再使用上面的 Hann
三点公式得到约 `delta=+0.4`，最终频率为：

```text
f_est = (k+delta)*Fs/N
```

为了避免浮点运算，RTL 把 `k+delta` 保存为 Q15，并利用
`488.28125=15625/32` 做精确的定点换算：

```text
frequency_hz = round(((k+delta)_q15 * 15625) / 2^20)
```

Q1.15 偏移本身对应约 `488.28125/32768=0.0149 Hz` 的数值步进，输出寄存器
最终舍入为整数 Hz。这里的 0.0149 Hz 只是定点计算分辨率，不代表整机绝对误差
达到 0.0149 Hz；真实准确度还受 2 MHz 采样时钟误差、噪声、量化、多音主瓣
叠加和模拟前端影响。题目要求为 1 kHz，当前算法给这些误差留下了充足裕量。

10 kHz 是一个特别的下边界：`10000/488.28125=20.48`，最大整数谱点可能是
bin 20。搜索若从 bin 21 开始，会丢掉真正主峰并误选旁瓣，所以当前搜索范围从
bin 20 开始，而最终测量带仍按插值频率判定为 10--500 kHz。

三峰寄存器按功率从强到弱排序，并不按频率排序。峰值功率低于最强峰的
`1/2048` 时不计入 `component_count`，对应幅值门限约 2.21%。单音测试中
`peak1/peak2_bin` 仍可能保留噪声局部峰；只有 `component_count` 指示的前若干
个峰及其幅值才有效。`fundamental_frequency_hz` 取所有合格分量中频率最低者。

### 精度验证与源码对应关系

自动回归包含五个完整 4096 点帧：500 kHz 单音、三音组合、10 kHz 下边界、
13 kHz 单音和偏离整数 bin 0.4 格的 300 kHz 单音。当前 XSim 结果为：

| 输入 | 期望峰值 code | RTL 频率 | RTL 峰值 code |
|---|---:|---:|---:|
| 500 kHz 单音 | 800 | 500000 Hz | 800 |
| 100.098/250/450.195 kHz 三音 | 1000/300/120 | 100098 Hz（基波） | 1000/300/120 |
| 10 kHz 单音 | 700 | 10000 Hz | 700 |
| 13 kHz 单音 | 650 | 13000 Hz | 650 |
| 300 kHz、偏移 0.4 bin | 900 | 300000 Hz | 900 |

板测 50 kHz、400 mVpp 得到 `peak0_bin=102`、插值频率 50000 Hz、幅值约
6330 code；全频域扫频时幅值波动约在 +/-100 code 内。绝对电压仍应以 ADC
BNC 端实测 Vpp 建立 `mV/code`，并在需要时用 `K(f)` 表补偿模拟前端频响。

主要实现文件如下：

- `g_fft_input_stream.v`、`g_hann_rom.v`：Q15 对称 Hann 加窗；
- `g_spectrum_analyzer.v`：功率、局部峰、三峰排序、门限和结果调度；
- `g_integer_sqrt.v`、`g_fractional_divider.v`：三点幅度与 Q1.15 偏移；
- `g_hann_peak_refiner.v`：频率偏移及 Hann 栅栏损失多项式；
- `g_hann_amplitude_scaler.v`：块浮点指数和相干增益恢复；
- `generate_g_fft_spectrum_vectors.m`、`tb_g_fft_spectrum.sv`：位真向量和五帧自检。

自检命令为：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_board_ila_build.ps1
```

当前校准/UART板测镜像已通过正式门禁：6521 LUT、11906 FF、29 BRAM tile、
35 DSP，200 MHz WNS `+0.016 ns`、WHS `+0.034 ns`，TNS/THS均为0；DRC无
Error/Critical Warning，未约束内部端点为0。`.bit/.ltx` 位于
`results/board_ila/`。由于建立时间裕量较小，任何RTL或ILA改动后都必须重新
执行完整实现。上一版FFT内部ILA说明保存在
`hardware/notes/fft_spectrum_ila_test_guide.md`；
当前校准/UART精简ILA以 `hardware/notes/tjc_calibration_board_test_guide.md` 为准。

### 电压校准与 UART 物理量接口

`g_measurement_calibrator.v` 已把 FFT 输出的三个幅值码转换为可直接交给 UART 的
物理量：三个分量按频率从低到高输出整数 Hz、峰值 uV 和 RMS uV，同时输出合成
信号的真 RMS。增益使用 Q16.16 `uV/code`，支持 UART/Flash 直接写系数，也支持
对已知 Vpp 单音自动平均 16 帧完成现场校准。默认系数只是由当前板测估出的临时
值，模拟前端确定后仍须在 50 ohm 条件下正式标定。

独立自检和 200 MHz 综合命令：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_calibrator_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_calibrator_synth.ps1
```

非统一相位的谐波仍可由复数 FFT 模长分离；当前端到端 Testbench 已用三个不同
初相位覆盖这一情况。接口定义、校准公式、板级步骤、UART 字段和无串口虚拟触发
方法见 `hardware/notes/measurement_calibration_interface.md`。

TJC4827T143 已使用115200/8-N-1接入：W18为FPGA TX、W19为FPGA RX。屏幕
发送 ASCII `C` 触发200 mVpp现场校准；板载R19/PL KEY1按下后，经20 ms消抖
只发送一次最近测量值到 `x0/x2/x3/x4`，不做周期刷新。屏幕配置、接线安全、
精简ILA探针和二次谐波测试步骤见
`hardware/notes/tjc_calibration_board_test_guide.md`。

在上述 XSim 脚本后增加 `-Gui` 可直接打开波形窗口。进入 Tcl Console 后执行
`source scripts/wave_adc_frontend.tcl`、`source scripts/wave_g_fir.tcl` 或
`source scripts/wave_g_frame.tcl`、`source scripts/wave_g_fft_input.tcl`；集成流水
使用 `source scripts/wave_g_pipeline.tcl`。变量说明见
`hardware/notes/waveform_guide.md`。
