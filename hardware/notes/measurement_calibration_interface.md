# 频谱测量值校准与 UART 接口

更新日期：2026-08-01
适用模块：`g_spectrum_analyzer.v`、`g_measurement_calibrator.v`

## 1. 赛题量值定义

赛题给出的分量形式为 `Ui*sin(i*w*t+phi_i)`，因此分量幅度 `Ui` 是正弦峰值，
不是峰峰值。校准模块统一使用整数微伏，避免 UART 侧承担浮点运算：

- `componentN_frequency_hz`：分量频率，单位 Hz；
- `componentN_amplitude_uv`：分量峰值 `Ui`，单位 uV；
- `componentN_rms_uv`：该正弦分量的有效值 `Ui/sqrt(2)`，单位 uV；
- `total_true_rms_uv`：所有不同频率分量合成后的真有效值，单位 uV；
- `component_count`：本帧有效分量数，范围 0--3；
- `measurement_valid`：上述整组输出同时更新的一拍脉冲。

三个分量输出按频率从低到高排列，所以 `component0` 是基波，后两项是谐波。
当 `component_count` 小于 3 时，未使用项的频率、幅度和有效值均为 0。

对于不同频率的谐波，任意初相位均满足正交关系，因此：

```text
component_rms_i = amplitude_i/sqrt(2)
total_true_rms = sqrt((amplitude_0^2+amplitude_1^2+amplitude_2^2)/2)
```

这两个结果不依赖各分量相位。总合成波形的峰峰值却依赖相位，不能把三个峰值
简单相加；它应由时域帧的 `max-min` 单独测量。校准模块当前没有取代该时域
峰峰值分支。

## 2. 为什么能分离非统一相位的叠加波

FFT 对每个频率给出复数结果 `X[k]=real+j*imag`。峰值搜索使用
`|X[k]|^2=real^2+imag^2`，相位只改变 real/imag 的比例，不改变模长。因此只要
各谐波频率可分辨、幅度超过检测门限且没有饱和，非统一初相位不会妨碍频率和
幅度分离。

`tb_g_fft_spectrum.sv` 的三音帧已使用三个不同相位
`-0.31 rad`、`+0.77 rad`、`-1.13 rad`，端到端检查三项频率、峰值、电压和
有效值。当前三峰门限仍为相对最强峰幅度约 2.21%；低于门限的极弱分量可能不被
计入，这和相位无关。

## 3. 校准系数

`active_gain_q16` 是无符号 Q16.16，物理单位为 `uV/code`：

```text
component_amplitude_uv = round(amplitude_code*active_gain_q16/65536)
```

接口宽度为 24 bit，可表示 `0...255.9999847 uV/code`。默认系数
`2070648/65536 = 31.59558 uV/code` 只来自现有 50 kHz、400 mVpp 板测的
约 `6330 code`，是上电临时值，不是最终计量标定结果。

有两种写入方式：

1. `gain_write=1` 一拍，同时给出非零 `gain_write_q16`。适合 UART/Flash 恢复
   已保存的系数；`calibration_done` 随后脉冲。零系数会置
   `calibration_error`，并保留原有有效系数。
2. `calibrate_start=1` 一拍，同时给出已知单音的
   `calibration_reference_vpp_uv`。模块平均随后 16 帧的最强峰值码，再计算：

```text
active_gain_q16 = round((reference_vpp_uv/2)*65536/average_peak_code)
                = round(reference_vpp_uv*32768/average_peak_code)
```

自动校准期间 `calibration_busy=1`。16 帧必须都被识别为单音且峰值非零；否则
`calibration_done=1`、`calibration_error=1`，并保留原系数。顺利完成时
`calibration_done=1`、`calibration_error=0`。除法器每拍处理一位，校准完成还需
约 40 个 200 MHz 时钟，远小于赛题 2 s 限制。

## 4. 推荐板级校准步骤

1. ADC 输入与信号源、电缆均按 50 ohm 系统连接；信号源负载设置为 `50 Ohm`，
   直流偏置为 0。
2. 预热后输入 100 kHz、200 mVpp 单音。该点位于通带中部且幅度不易触及 ADC
   满量程。若已接模拟前端，应从装置 BNC 输入端施加标准信号。
3. 触发 `calibrate_start`，参考值写 `200000 uVpp`，等待
   `calibration_done`，确认 `calibration_error=0`。
4. 将 `active_gain_q16` 保存到非易失存储；下次上电通过 `gain_write` 恢复。
5. 用 50、100、200、300、500 kHz 以及 50/100/250 mVpp 交叉复核。若残差随
   频率呈系统变化，单个标量增益不够，应在模拟前端定型后加入分段 `K(f)` 频响
   校正表；不要用 FFT 的 Hann 修正系数替代模拟频响校准。

自动校准应使用纯净单音。多音校准、ADC 饱和、连接器接触不良或信号源负载模式
错误都会导致错误系数。

## 5. UART 对接建议

UART 发送器只在 `measurement_valid=1` 时锁存整组输出。建议固定发送以下字段：

```text
component_count                 2 bit
component0_frequency_hz        20 bit
component0_amplitude_uv        24 bit
component0_rms_uv              24 bit
component1_frequency_hz        20 bit
component1_amplitude_uv        24 bit
component1_rms_uv              24 bit
component2_frequency_hz        20 bit
component2_amplitude_uv        24 bit
component2_rms_uv              24 bit
total_true_rms_uv              24 bit
measurement_overrun             1 bit, sticky health flag
calibration_error               1 bit
```

UART/屏幕层仅负责小数点格式化，例如 `100001 Hz`、`100000 uV` 显示为
`100.001 kHz`、`100.000 mV`。不要再次乘 2：`amplitude_uv` 已是赛题要求的
分量峰值；若界面另需分量 Vpp，才计算 `2*amplitude_uv`。

`measurement_overrun` 表示新频谱结果到达时上一组换算尚未结束。正常 FFT 帧率下
它应始终为 0；该位为粘滞错误，只在复位时清零。

## 6. 无 UART 的虚拟输入/触发验证

独立校准自检不需要 ADC、串口屏或信号源：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_calibrator_xsim.ps1
```

该 Testbench 会虚拟产生频谱结果脉冲，并自动检查：

- 三个功率乱序的峰是否按频率重排；
- 直接增益写入和非法零增益保护；
- `200 mVpp / 4000 code`、连续 16 帧自动校准是否得到精确
  `25 uV/code`；
- 三项峰值、各分量 RMS、总真有效值和输出 valid；
- 忙时重复输入是否置 `measurement_overrun`。

需要查看虚拟触发和换算流水时运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_calibrator_xsim.ps1 -Gui
```

GUI 启动后执行 `Run All`。脚本会自动加载
`scripts/wave_g_measurement_calibrator.tcl`。完整算法端到端验证使用：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1
```

独立校准模块已按 5 ns 时钟约束综合，报告位于
`results/synth_g_measurement_calibrator/`。UART 尚未接入时，板级顶层把写系数和
自动校准触发保持为 0；UART 队友接线时应把这些控制和本节输出接到寄存器/发送器。

## 7. 相位支路与校准边界

`g_phase_estimator.v` 从同一份 4096 点 Hann 帧旁路计算相位，不进入上述
`uV/code` 幅值换算。其稳定输出接口为：

```text
phase_results_valid          整对结果更新的一拍脉冲
harmonic1_phase_valid        第一个高次分量是否为有效谐波
harmonic1_phase_deg[8:0]     0..359 度
harmonic2_phase_valid        第二个高次分量是否为有效谐波
harmonic2_phase_deg[8:0]     0..359 度
```

相位采用赛题正弦定义，并输出
`wrap360(phi_h-round(f_h/f_1)*phi_1)`。UART 收到 `P/0x50` 后，将两路有效角度
发送到相位页 `x0/x1`；无效项发送 999，基波由屏幕固定显示 0°。

现场 100 kHz/200 mVpp 定标只求电压增益，不能修正模拟前端相移。纯延时会在
相对相位中抵消，但模拟通道的非线性相频响应不会；如实板误差随频率可重复变化，
需要另建频率相关的相位校准表。相位是超指标展示，不改变赛题规定的频率、Um、
整体 Vpp 和真 RMS 验收链。
