# 2026 电赛 G 题 FPGA 周期信号测量分析装置

本仓库实现“周期信号测量分析装置”的 MATLAB 黄金模型、定点化、RTL、XSim 自检、Vivado 板级工程和陶晶驰串口屏显示。本文按信号实际流经系统的顺序组织，重点回答三个问题：每一级为什么存在、做了什么数学处理，以及浮点算法怎样变成可在 Zynq-7020 上以 200 MHz 运行的硬件。

## 1. 题目、硬件与当前边界

题目要求在 2 s 内分析由基波和一至两个谐波组成的周期信号，显示一或三个完整周期、整体峰峰值、真有效值、基波频率、定性频谱和各分量峰值幅度。幅值绝对误差限为 5 mV，基波频率误差限为 1 kHz，频率分辨率要求 500 Hz。

- 任务 1：整体 100～250 mVpp，各分量 10～200 kHz。
- 任务 2：整体 50～250 mVpp，各分量 10～500 kHz。
- 任务 3：在任务 2 信号上叠加 200 mVpp、1 MHz 及以上单音干扰，仍测量有用信号。
- 输入、信号源和同轴电缆均按 50 Ω 系统使用。信号发生器必须选择 `50 Ω` 负载，题目以信号源设置值为标称值。

当前硬件为 MicroPhase Mizar Z7（`xc7z020clg400-2`）、ADS6149 14 bit ADC 和 TJC8048X270_11 串口屏。板载参考时钟为 50 MHz，ADC 和系统高速逻辑按 200 MHz 工作。ADC 返回时钟和数据采用厂商例程对应的 `HSTL_II_18` 与 Bank 35 `INTERNAL_VREF=0.9 V`；W18/W19 串口引脚采用 `LVCMOS33`。不能因为普通 FPGA 控制信号为 3.3 V，就把 ADC 高速数据脚改成 `LVCMOS33`。

当前仍有两个必须记住的物理边界：

1. 板上 ADC `CLKOUT` 位于 L20，工程使用了 `CLOCK_DEDICATED_ROUTE FALSE`。最终实现已过时序，但这不是理想的专用时钟布线。
2. 目前没有正式的模拟抗混叠低通。数字滤波能抑制仍留在数字域中的 1 MHz 以上分量，却不能恢复第一次抽取时已经混叠进 0～500 kHz 的信息。任务 3 的最终可靠性仍依赖 50 Ω 输入、ADC 驱动和模拟低通。

硬件手册、原理图、ADS6149 数据手册和厂商参考工程位于 `docs/`，该目录不提交 Git。厂商工程由较新 Vivado 生成，只用于提取引脚、I/O 标准、接口结构和 IP 参数，不能直接由 Vivado 2020.2 覆盖保存。

## 2. 从 MATLAB 到上板的完整工作流

```text
赛题指标与测试用例
    ↓
MATLAB 浮点黄金模型：验证算法是否有能力达标
    ↓
MATLAB 定点分析：确定 FIR、Hann、位宽、舍入和参考向量
    ↓
RTL：按 200 MHz 时序、BRAM/DSP 资源和 valid/ready 协议实现
    ↓
XSim：读取 MATLAB 向量，逐拍比较，形成可重复的自检闭环
    ↓
Vivado 综合/实现：检查资源、时序、DRC、CDC 与实际 XDC
    ↓
无 ILA 的 release bit + Hardware Manager：用真实 ADC、50 Ω 信号源验证
    ↓
现场单音校准 → UART 数值和 800 点图形 → 串口屏
```

这个顺序很重要。MATLAB 解决“数学方法是否成立”；位真向量解决“定点和 RTL 是否等价”；XSim 解决“协议和边界是否正确”；时序报告解决“电路是否跑得动”；最终板测解决“真实引脚、时钟、ADC 码制和模拟链路是否正确”。当前 release 已去掉 ILA，早期 ILA 数据仅作为调试历史，不能替代前面几层验证。

## 3. MATLAB 阶段具体做了什么

### 3.1 浮点黄金模型

`matlab/model/g_measurement_model.m` 是算法参考。它依次执行：

1. 200 MSPS 数据每 10 点取 1 点，得到 20 MSPS；
2. 设计并应用 255 tap、800 kHz 截止的 Kaiser 窗低通；
3. 再每 10 点取 1 点，得到 2 MSPS；
4. 取 4096 点、去均值、乘 Hann 窗并做 FFT；
5. 在题目 10～500 kHz 范围内搜索最多三个局部峰；RTL release 另将内部范围扩展到 1～600 kHz；
6. 用三点对数抛物线插值得到亚 bin 频率；
7. 在这些频率上建立正弦/余弦矩阵，以最小二乘法同时拟合各分量幅值和相位；
8. 除以 FIR 在对应频率处的复频响，补偿数字滤波幅频响应；
9. 根据拟合出的多音信号计算整体 Vpp、真 RMS、单周期和三周期波形。

若检测到频率为 `f_i` 的若干分量，模型建立

```text
x[n] ≈ c + Σ(a_i cos(2πf_i n/Fs) + b_i sin(2πf_i n/Fs))
```

用最小二乘求解系数后，单个分量的峰值和相位为

```text
A_i = sqrt(a_i²+b_i²)
phi_i = atan2(-b_i, a_i)
```

它比只读取一个 FFT bin 更接近“计量算法”，也能处理不同初相位；代价是矩阵求解不适合直接照搬到当前 FPGA。RTL 因而使用更便宜的 Hann 三点插值和幅值补偿。换言之，MATLAB 是精度上限和交叉检查工具，不是 RTL 的逐语句翻译。

`matlab/model/run_g_model_regression.m` 构造覆盖三项任务的确定性测试：不同基频、谐波阶次、初相位、50～250 mVpp 输入，以及 1 MHz、1.37 MHz、5 MHz 干扰；还加入直流偏置、14 bit/2 Vpp ADC 量化和小量噪声。每例自动检查分量数、频率、各分量幅值、整体 Vpp 和 RMS 是否落入题目误差预算，结果写入 `results/g_model_regression.csv`。

### 3.2 FIR 设计与定点化

`g_design_lowpass.m` 用窗函数法设计理想低通。对奇数长度 `N=255`，中心位置为 127：

```text
h_ideal[n] = 2fc/Fs · sinc(2fc/Fs · (n-127))
h[n]       = h_ideal[n] · Kaiser(n, beta)
h[n]       = h[n] / Σh[n]
```

当前参数为 `Fs=20 MHz`、`fc=800 kHz`、`beta=7.86`。`analyze_g_fixed_fir.m` 将系数量化为 signed Q1.17，并修正中心抽头，使整数系数之和严格等于 `2^17`，因此直流增益严格为 1。它还验证对称性、累加器位宽与频响：

| 项目 | 当前结果 |
|---|---:|
| 通带 0～500 kHz 波纹 | 0.001899 dB |
| 500 kHz 增益 | +0.000095 dB |
| 1 MHz 起最差阻带 | -73.347 dB |
| 所需累加器 | 32 bit |
| 量化后对称误差 | 0 LSB |

截止频率选在 800 kHz，是在“500 kHz 内尽量平坦”和“1 MHz 起快速衰减”之间留过渡带；量化后 1 MHz 起仍有 73 dB 以上抑制。提高截止频率并不是 500 kHz 故障的主要修复，真正的边界问题在峰值搜索对最后合法 bin 的判定。数字低通也不等于允许先把 200 MSPS 无滤波抽到 20 MSPS：第一次 `/10` 之前的模拟抗混叠责任仍存在。

### 3.3 MATLAB 如何成为 RTL 的裁判

MATLAB 不只画图，还生成可被 Testbench 读取的位真文件：

- `generate_adc_frontend_vectors.m`：ADC 二补码/偏移二进制与抽取边界；
- `generate_g_fir_vectors.m`：Q1.17 FIR 逐点期望值；
- `generate_g_frame_vectors.m`：第二级抽取和帧边界；
- `generate_g_hann_vectors.m`：4096 点 Hann 的前半 ROM，以及小规模逐点乘法期望值；
- `generate_g_pipeline_vectors.m`：ADC 码到 FFT 输入前的端到端期望值；
- `generate_g_fft_spectrum_vectors.m`：1 kHz 下边界、精确/非相干 500 kHz、600 kHz 上边界、不同初相位，以及弱基波三音的十三帧频谱测试。

例如 Hann 定点乘法不是笼统的“乘 0.5”，而是明确规定：

```text
w_q15[n] = round(w[n]·32767)
y[n]     = floor((x[n]·w_q15[n] + 2^14)/2^15)
```

MATLAB 与 RTL 使用同一舍入规则，Testbench 才能逐 bit 比较，而不是容忍“看起来差不多”。

## 4. FPGA 中信号逐级经历了什么

板级顶层为 `g_board_ila_top.v`，主要模块关系如下。表中的速率是“有效样本率”，各模块本身都处于 200 MHz 系统时钟域，只有 ADC 输入 IOB/FIFO 写端位于 ADC 返回时钟域。

| 数据阶段 | 主要模块 | 输入/输出 | 主要职责 |
|---|---|---|---|
| 板级时钟与 CDC | `g_board_ila_top.v` + XPM FIFO | ADC 200 MSPS → 系统域 | IOB 采样、异步跨域、错误状态同步 |
| 采样前端 | `adc_sample_frontend.v` | 200 → 20 MSPS | 码制归一化、第一次 `/10` |
| 数字低通 | `g_symmetric_fir.v` | 20 → 20 MSPS | 255 tap Q1.17 FIR |
| 频谱帧 | `g_frame_capture.v` | 20 → 2 MSPS | 第二次 `/10`、4096 点 ping-pong 缓存 |
| FFT 输入 | `g_fft_input_stream.v` | 4096 点帧 | Q1.15 Hann、AXI Stream 握手 |
| 频域变换 | `g_fft_core_wrapper.v` | 实数时域 → 复数频域 | Vivado FFT 配置、bin 与 block exponent |
| 参数提取 | `g_spectrum_analyzer.v` | 复数 bin → 三个分量 | 功率、峰搜索、频率插值、幅值补偿 |
| 物理量换算 | `g_measurement_calibrator.v` | code → μV/Hz | 校准、频率排序、Um 与真 RMS |
| 结果稳定门 | `g_measurement_stabilizer.v` | 连续测量帧 → 稳定结果 | 两帧一致性判断、拒绝改频/开关通道的过渡帧 |
| 时域显示 | `g_time_domain_display.v` | 20 MSPS FIR 流 → 800 点 | 环形缓存、整体 Vpp、一/三周期图 |
| 频谱显示 | `g_spectrum_display.v` | 0～600 kHz 功率 → 800 点 | max-pooling、开方、归一化 |
| 人机接口 | `g_tjc_display_uart.v` | 物理量/图 → UART | 按键、消抖、BCD、透明传图与快照 |

### 4.1 ADC 采集、码制和跨时钟域

```text
ADS6149 14 bit / 200 MSPS
    → 输入 IOB 寄存
    → 按配置解释为二补码或 offset binary
    → ADC 返回时钟域异步 FIFO
    → 200 MHz 系统时钟域
```

`adc_sample_frontend.v` 将 ADC 原始码统一成 signed 二补码。若 ADC 输出是 offset binary，则只需翻转 MSB；当前板级配置 `ADC_OFFSET_BINARY=0`，表示直接按二补码解释。之后每 10 个有效样本输出一个，数据率由 200 MSPS 降为 20 MSPS。

异步 FIFO 不是为了滤波，而是隔离 ADC 返回时钟与 FPGA 系统 200 MHz 时钟的相位关系。写指针和读指针经过 CDC 同步，读取端等待约 16 点预填充，吸收指针同步延迟，避免输出 valid 周期性断裂。调试时应以 `valid` 判断数据是否有效，不能因为数据寄存器数值稳定就推断通路停止。

### 4.2 255 tap 对称 FIR：为什么只用 13 个乘法通道

普通 FIR 为

```text
y[n] = Σ(k=0..254) h[k]x[n-k]
```

线性相位系数满足 `h[k]=h[254-k]`，所以可以改写为

```text
y[n] = Σ(k=0..126) h[k](x[n-k]+x[n-254+k]) + h[127]x[n-127]
```

独立乘法从 255 次降为 128 次。输入有效率是 20 MSPS，而计算时钟是 200 MHz，每个输入样本之间恰有 10 个系统周期；`g_symmetric_fir.v` 使用 13 条 DSP 乘法 lane，分 10 个 phase 完成 `13×10=130` 个位置，覆盖 128 个唯一抽头。这样没有堆出 128 个并行乘法器，同时又能持续接收 20 MSPS。

每级乘积先进入寄存器，再用多级加法树汇总，最后对 Q1.17 结果对称舍入并饱和到 16 bit。核心工程思想是利用“数据率比时钟慢 10 倍”的时间预算换资源，而不是为了省 DSP 把 128 项塞进一个超长组合路径。

### 4.3 第二次抽取与 ping-pong 帧缓存

`g_frame_capture.v` 对 FIR 输出再 `/10`，形成 2 MSPS、4096 点帧：

```text
帧时长 = 4096 / 2,000,000 = 2.048 ms
```

帧缓存使用 ping-pong 双 BRAM：一块继续采下一帧，另一块供 FFT 读取。FFT 的 AXI Stream 可能因内部处理拉低 `ready`，双缓存可将连续采样与突发读帧解耦；处理完成后通过 release 握手归还 bank。若只有单 RAM，采样写入与 FFT 读取会争用端口，背压还可能破坏固定采样间隔。

### 4.4 Hann 加窗与 FFT

4096 点对称 Hann 为

```text
w[n] = 0.5 - 0.5cos(2πn/(N-1)),  N=4096
```

左右对称使 FPGA 只保存前 2048 个 Q1.15 系数，后半窗镜像寻址，ROM 减半。`g_fft_input_stream.v` 把帧样本乘窗、舍入，然后通过 valid/ready/last 送给 Vivado FFT v9.1。FFT 参数为 4096 点、自然顺序、16 bit 定点、block floating point、Non-Realtime。

Hann 窗降低非整周期截断造成的旁瓣泄漏，但一定会衰减幅值。“无衰减加窗”的工程含义不是窗本身无损，而是窗后按已知增益恢复。若峰恰在 bin 中心：

```text
Mcenter ≈ A · N · CG / 2 · 2^(-B)
CG = Σw[n]/N ≈ 0.499878
N·CG/2 = 1023.75 ≈ 2^10
Acenter ≈ Mcenter · 2^(B-10)
```

`B` 是 FFT block exponent。`g_hann_amplitude_scaler.v` 每拍移一位来恢复指数，避免 200 MHz 路径上出现宽桶形移位器。用 1024 近似 1023.75 的固定误差约 0.0244%，最终可由整机校准吸收。

### 4.5 bin、峰值搜索和亚 bin 频率

FFT 的 bin 是离散频率格点编号：

```text
Δf = Fs/N = 2,000,000/4096 = 488.28125 Hz
f[k] = k·Δf
```

例如 50 kHz 对应 `k=102.4`，所以整数最大点通常是 bin 102，但真实频率不等于 `102×488.28125`。`g_spectrum_analyzer.v` 在 release 中扫描 bin 2～1229（约 1～600 kHz；题目保证范围仍为 10～500 kHz）并计算

```text
P[k] = Re[k]² + Im[k]²
```

并寻找局部极大值。三峰最初按功率由强到弱保存；低于最强峰功率 `1/2048` 的候选不计入 `component_count`，相当于幅值约低于最强峰 2.21%。校准模块随后把有效分量按频率升序排列，因此屏幕 `x2/x3` 总是最低频分量，而不是最强分量。

对峰点左、中、右幅度

```text
L=sqrt(P[k-1]), C=sqrt(P[k]), R=sqrt(P[k+1])
```

RTL 估计 Hann 主瓣中的小数偏移：

```text
delta = 2(R-L)/(L+2C+R),  -0.5 ≤ delta ≤ 0.5
f_est = (k+delta)Fs/N
```

`delta` 用 signed Q1.15。由于 `488.28125=15625/32`，硬件可写成

```text
frequency_hz = round(((k+delta)_q15 · 15625)/2^20)
```

Q15 运算步进约 0.0149 Hz，但这只是数字表示分辨率，不代表测量准确度。真实误差还来自采样时钟、噪声、相邻主瓣、量化和模拟频响。1 kHz 位于 bin 2.048，release 从 bin 2 开始搜索；10 kHz 位于 bin 20.48，不能从 bin 21 才开始，这正是早期 10 kHz 被误判约 16.7 kHz 的根因之一。

### 4.6 非整数 bin 的幅值为什么还能稳定

非整数 bin 会产生 scalloping loss。以 300 kHz 为例，它位于 bin 614.4，只读 bin 614 时 Hann 峰值约只剩 0.9008，即约 -0.91 dB。项目用同一个 `delta` 做偶次多项式修正：

```text
Hcorr(delta) ≈ 1 + 0.64744225delta² + 0.25902453delta⁴
Ccorrected   = C·Hcorr(delta)
```

两个系数量化为 Q16 的 `42431` 和 `16975`，拟合范围 `[-0.5,0.5]` 内最坏误差约低于 0.03%。之后再恢复 block exponent 和 Hann 相干增益，得到正弦峰值 `amplitude_code`。这解释了扫频时同一输入幅值的 code 基本不随 bin 位置变化。

当前 XSim 十三帧自检覆盖 1 kHz 下边界、精确 500 kHz 的不同相位、499.5/499.9/500.1 kHz 邻域、600 kHz 上边界，以及基波明显弱于二/四次谐波且各自带相位的三音输入。频率与幅值均回到期望值，说明这些条件在纯数字 Hann/FFT/峰值算法中可重复通过；若上板仍出现历史状态依赖，应优先检查 ADC/FIFO/帧握手和信号源状态。

### 4.7 电压校准、分量 Um 与真 RMS

FFT 输出仍是 ADC 幅值码。`g_measurement_calibrator.v` 保存 unsigned Q16.16 的增益

```text
G = 微伏/幅值码
U_i(μV, peak) = round(amplitude_code_i · G)
```

屏幕按题目定义显示各分量峰值 `Um`，不是 Vpp。单个正弦有

```text
Vpp_i = 2U_i
Vrms_i = U_i/sqrt(2)
```

现场校准按钮发送 ASCII `C` (`0x43`)。系统要求输入 100 kHz、200 mVpp 单音，验证仅有一个分量且频率在 99～101 kHz，连续平均 16 帧后计算

```text
Uref = Vpp_ref/2 = 100000 μV
G_q16 = round((Uref << 16)/average_code)
```

平均 16 帧降低短期噪声，单音和频率检查避免误用多音完成标定。当前校准掉电后不保存，但赛场可重新一键校准；若以后需要掉电保持，可通过 `gain_write_q16` 从 Flash/UART 恢复。

不同频率的正弦在整数个基波周期上互相正交，因此零直流条件下总真有效值为

```text
Vrms_total = sqrt(Σ U_i²/2)
```

该结果与各分量初相位无关。RTL 先对幅值码平方、求和、除 2、做整数平方根，最后统一乘增益；分量 RMS 则乘 Q16 常数 `1/sqrt(2)=46341/65536`。

整体 Vpp 不满足 `2ΣU_i`，因为各谐波峰值一般不同时出现，而且它取决于相位。RTL 的 `g_time_domain_display.v` 保存 8192 点 20 MSPS FIR 输出，在最近三个基波周期中直接求 `max-min`，再乘校准增益。这样无需恢复每个分量相位，也能测真实合成波峰峰值。

一个实测例子很能说明区别。信号源设置基波/2 次/4 次谐波 Vpp 为 50/200/250 mV，屏幕得到 `Um=25/101/126 mV`，则

```text
Vrms = sqrt((25²+101²+126²)/2) = 115.55 mV ≈ 116 mV
u(t) = 25sin(wt)+101sin(2wt)+126sin(4wt) mV
max(u)-min(u) = 425.88 mV ≈ 426 mV
```

所以当时显示的 426 mVpp 和 116 mVrms 与三个分量完全自洽；不能用 `2×(25+101+126)=504 mV` 判断整体 Vpp 错误。

校准之后还有一层 `g_measurement_stabilizer.v`。它不做平均，也不修改频率/幅值，只要求连续两帧的分量数一致，并且对应分量满足频率差不超过 1 kHz、幅值和总 RMS 差不超过 5 mV，第二帧才发布给屏幕。信号源关断、改频、再打开时产生的第一帧会被挡住；代价仅增加一帧约 2.048 ms，远低于 2 s 限制。

### 4.8 一周期/三周期波形与定性频谱

时域显示根据最低频分量计算

```text
period_samples = round(20 MHz/f0)
```

从环形 BRAM 快照中选取一或三个周期，以 Q16 地址步长重采样为 800 点，再按本次扫描的 min/max 归一化到 0～255。它是定性波形，纵轴自动铺满，不可从图高直接读取 mV；数值应看 `x0..x7`。

频谱显示将正频率 bin 0～1229（0～600 kHz）映射到列 24～775，左右各保留 24 点空白，使两侧边界谱线不会被控件裁去一半。同一列落入多个 bin 时取最大功率，再开平方变回与电压幅值成正比的量，最后相对全谱最大值归一化到 0～255。绘图支路将 bin 0/1 强制清零，避免 ADC 零点偏置和 Hann 首裙边合并成左侧冲激；测量支路仍保留 bin 1 作为真实 bin-2/1 kHz 峰的插值护栏。若直接显示功率，较小谐波会按幅值平方被压得过低。

时域图不是改变测量数据，而是只在显示支路对相邻真实样点做线性插值。500 kHz 在 20 MSPS 下每周期有 40 个真实点，直接最近邻扩展到 800 列会出现长平台；插值后的曲线更连续，同时 Vpp、RMS、FFT 与校准仍使用原始样本，不会为了“好看”篡改测量值。

## 5. 串口屏协议与交互

TJC8048X270_11 使用 115200、8-N-1：FPGA TX=W18，RX=W19。R19/PL KEY1 低有效，经过 20 ms 消抖，每次按下只发送一次完整页面，不做周期刷新。

| 控件 | FPGA 发送值 | 屏幕显示 |
|---|---|---|
| `x0` | 整体 Vpp，10 μV/LSB | mV（两位小数） |
| `x1` | 整体真 RMS，10 μV/LSB | mV（两位小数） |
| `x2` / `x3` | 最低频分量 Um（10 μV/LSB）/ 频率（1 Hz/LSB） | mV（两位）/ kHz（三位） |
| `x4` / `x5` | 第二分量 Um（10 μV/LSB）/ 频率（1 Hz/LSB） | mV（两位）/ kHz（三位） |
| `x6` / `x7` | 第三分量 Um（10 μV/LSB）/ 频率（1 Hz/LSB） | mV（两位）/ kHz（三位） |
| `s0` | 800 个 8 bit 点 | 800×256 定性图 |

幅值由 μV 四舍五入为 10 μV 单位，例如 246800 μV 发送 `24680`，控件设两位小数后显示 `246.80 mV`。频率以整数 Hz 原样发送，例如 12345 Hz 发送 `12345`，控件设三位小数后显示 `12.345 kHz`。按钮返回 ASCII：`C=0x43` 校准、`1=0x31` 单周期、`3=0x33` 三周期、`S=0x53` 频谱。

图形先发送 `cle s0.id,0` 清除旧轨迹，再发送 `addt s0.id,0,800` 和三个 `0xFF`；收到屏幕 `0xFE` 后发送 800 个原始字节，等待 `0xFD` 完成。发送前先把显示 RAM 复制到快照 BRAM，防止 UART 慢速传输期间后台更新造成画面前后半帧不一致。FE/FD 等待均有超时回收，丢失一次握手不会让模式按钮永久卡死。

## 6. 工程实现中最值得复盘的优化

### 6.1 用流水线换时序

200 MHz 只有 5 ns。实际遇到过的关键路径不是 FFT，而是“BRAM 读出→比较/减法→乘 255→除法”和峰值排序/换算。处理方法是把读取、比较、减法、乘法、除法启动和结果提交拆成多个寄存状态；三元素频率排序也拆成三个 compare/swap 周期。吞吐要求并不高的控制计算没有必要一拍完成。

整数平方根和除法器采用逐位迭代，每拍决定一位。它们延迟几十拍，但一帧要 2.048 ms，几十到几百纳秒几乎没有系统影响，却避免了巨大组合除法器。

### 6.2 让综合器真正推断 BRAM/DSP

一次频谱显示初版允许同周期写两个地址，Vivado 无法推断单/双口 BRAM，把 `800×33` 存储展开成触发器和大多路器，资源曾膨胀到约 14 万 LUT。当前设计把最后一列的 flush 单独放到下一拍，保证每拍最多一次写入，最终重新推断为 BRAM。

类似地，乘法前后显式寄存并使用合适位宽，帮助乘法吸收到 DSP48。Hann ROM 利用对称性减半；FIR 利用系数对称和 10 倍时分复用；FFT 帧用 BRAM 而不是寄存器阵列。这些优化都来自数据结构和速率关系，而不只是综合选项。

### 6.3 控制扇出、快照和错误可见性

- 高扇出 reset/enable 使用局部寄存副本和层次化控制，减少布线压力。
- 测量结果先锁存，再启动 BCD 和 UART；图形先快照，避免撕裂。
- 跨模块使用 `valid/ready/done/busy`，不靠固定延迟猜结果时间。
- overrun、FFT protocol error、UART framing error、transparent timeout 等错误采用 sticky 标志，便于仿真和内部状态闭环检查。
- 正式 release 不实例化 ILA，不占用调试 BRAM/LUT，也不需要 `.ltx`。历史 ILA 指南和导出文件仅用于复盘旧问题。

2026-07-31 最终无 ILA release 为 6339 LUT、11190 FF、44.5 BRAM tile、40 DSP；
200 MHz 建立裕量 `+0.073 ns`、TNS `0`，保持裕量 `+0.034 ns`、THS `0`，无未约束
内部路径，DRC 为 `0 Error / 0 Critical Warning`。用户确认的 `−0.104 ns` 临时上板
容许量最终没有用到；本镜像本身已满足建立/保持时序。裕量仍然较窄，任何 RTL、IP
或 XDC 改动后都必须完整重新实现，不能沿用旧 bitstream 的时序结论。

## 7. 验证闭环与常用命令

生成 MATLAB 模型结果和所有共享向量：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_model_regression.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fixed_fir_analysis.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_matlab_vectors.ps1
```

逐模块自检：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_adc_frontend_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fir_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_frame_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_input_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_fft_spectrum_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_calibrator_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_measurement_stabilizer_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_display_builders_xsim.ps1
powershell -ExecutionPolicy Bypass -File scripts/run_g_tjc_display_uart_xsim.ps1
```

ADC→FIR→帧→Hann 的端到端位真闭环：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_closed_loop.ps1
```

正式板级实现：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_board_ila_build.ps1
```

生成的 `g_board_release.bit` 和 `build_manifest.txt` 位于 `results/board_ila/`；release 不生成也不需要 `.ltx`。同目录若存在旧 `g_board_ila.ltx`，它只是历史产物，不能与 release bit 配套使用。若要观察 XSim 波形，在对应脚本后使用 GUI 方式运行，并在 Tcl Console 中 source `scripts/wave_*.tcl`。

上板验证建议按以下顺序，不要一开始就测复杂三音：

1. ADC 断开/零输入，检查时钟、复位、FIFO 和错误 sticky；
2. 100 kHz、200 mVpp、50 Ω 单音执行现场校准；
3. 固定 200 mVpp 扫 1、5、10、13、50、100、300、500、600 kHz，检查扩展范围；题目验收重点仍为 10～500 kHz；
4. 固定频率扫 50～250 mVpp，检查线性；
5. 输入已知二音/三音，分别核对 Um、频率、总 RMS 和相位相关的整体 Vpp；
6. 加入 1 MHz 以上干扰，评估模拟前端完成后任务 3 的抑制能力；
7. 最后验证串口屏按钮、R19 单次发送、透明传图和超时恢复。

## 8. 如何判断结果是否合理

- `component_count` 决定有几个分量有效；单音时残留的 `peak1/peak2_bin` 调试值不代表检测到了三个信号。
- 各分量在复数 FFT 上取模，因此不同初相位不会阻止频率和幅值分离；相邻频率若小于 Hann 主瓣可分辨范围，仍可能互相影响。
- 分量 `Um` 是峰值，信号源通常设置 Vpp，单音二者相差 2 倍。
- 总 RMS 可由各分量 Um 平方和验证；总 Vpp 必须用相位一致的合成波或时域 max-min 验证。
- 定性波形和频谱都自动归一化，图的高度不能代替数值标定。
- 幅值全频段一致并不证明绝对 mV 正确；前者主要验证 Hann/scalloping/FIR 补偿，后者由 50 Ω 条件下的整机校准决定。
- 频率显示到 1 Hz 不代表精度为 1 Hz；题目判据仍是与信号源标称值相差不超过 1 kHz。

## 9. 目录和开发环境

- `matlab/model/`：浮点模型、定点分析和向量生成器；
- `matlab/vectors/`：RTL/Testbench 共用的系数和黄金向量；
- `rtl/src/`：可综合 Verilog-2001 与 Vivado IP wrapper；
- `rtl/tb/`：自检 SystemVerilog Testbench；
- `rtl/constraints/`：板级 XDC；
- `scripts/`：MATLAB、XSim、综合、实现和波形脚本；
- `hardware/notes/`：接线、板测手册和历史 ILA 记录；
- `logs/`、`results/`：日志、报告、bitstream 和导出数据；
- `docs/`：本地赛题和厂商资料，不提交 Git。

本机基准环境为 MATLAB R2024b、Vivado/XSim 2020.2 和 Git 2.47.1。VS Code、MATLAB 和 Vivado 应引用同一份磁盘源码，不要复制进多个工程后分别修改，也不要同时在三个编辑器中保存同一文件。

## 10. 后续改进方向

1. 完成 50 Ω 模拟前端与 500 kHz 通带平坦、1 MHz 起衰减的抗混叠低通，并实测幅频响应。
2. 若模拟链路残余频响超过误差预算，引入按频率分段的 `K(f)` 增益表，而不是只用一个全频段标量。
3. 用高精度频率计或标准源测定 2 MHz 等效采样率误差，必要时增加频率校准系数。
4. 对相邻谱线、低信噪比和非谐波输入建立拒绝/置信度规则，防止把噪声峰作为有效谐波。
5. 若资源和时序允许，可把 MATLAB 的多正弦最小二乘拟合或 Goertzel 精修用于已检测频率附近；当前题目精度下不是必需项。
6. 最终硬件定型后重新执行 MATLAB、XSim、实现、50 Ω 标定和三项题目全量回归，并保存输入设置、release bit、报告与结果表，形成可追溯提交版本。
