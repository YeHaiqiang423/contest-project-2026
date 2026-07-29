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

2 MSPS 下 4096 点变换的频率间隔为 488.28125 Hz。频谱峰用于定位分量，随后
用正弦/余弦最小二乘拟合估计频率、相位和峰值幅度；`Urms` 根据谐波幅度计算，
`Upp` 在稠密重建的一个基波周期上求取。任务 3 必须同时依赖模拟和数字滤波：
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
自检命令为：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_board_ila_build.ps1
```

当前板级实现资源为 5898 LUT、11420 FF、71 BRAM tile、23 DSP；200 MHz 最终
WNS +0.184 ns、WHS +0.034 ns，DRC/CDC Critical 和未约束路径均为 0。新版 ILA
操作与校准说明见 `hardware/notes/fft_spectrum_ila_test_guide.md`。

在上述 XSim 脚本后增加 `-Gui` 可直接打开波形窗口。进入 Tcl Console 后执行
`source scripts/wave_adc_frontend.tcl`、`source scripts/wave_g_fir.tcl` 或
`source scripts/wave_g_frame.tcl`、`source scripts/wave_g_fft_input.tcl`；集成流水
使用 `source scripts/wave_g_pipeline.tcl`。变量说明见
`hardware/notes/waveform_guide.md`。
