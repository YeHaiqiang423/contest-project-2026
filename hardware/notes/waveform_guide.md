# XSim 波形变量速查

## 使用方法

进入项目根目录，以 GUI 模式启动仿真后，在 XSim 的 Tcl Console 中加载对应脚本：

```tcl
source scripts/wave_adc_frontend.tcl
```

或：

```tcl
source scripts/wave_g_fir.tcl
```

首次运行直接执行 `run all`；已经执行到 `$finish` 后，应先 `restart`，再执行
`run all`。原始 ADC 总线适合显示为十六进制，归一化后的数据适合选择
`Radix -> Signed Decimal`。

## ADC 前端

| 变量 | 含义 | 正常关系 |
|---|---|---|
| `clk_adc` | 200 MHz 算法时钟 | 周期 5 ns |
| `rst_n` | 低有效复位 | 解除后为 1 |
| `adc_valid` | 当前输入码有效 | 实板连续采集时通常恒为 1 |
| `adc_data_twos` | 二补码原始 ADC 码 | 与 offset 数据只差 MSB |
| `adc_data_offset` | 偏移二进制原始 ADC 码 | `twos XOR 0x2000` |
| `sample_valid_*` | 十倍抽取输出有效 | 每累计 10 个输入有效样点脉冲一次 |
| `sample_data_*` | 归一化后的有符号样点 | 两条通路在有效时必须相同 |
| `decimation_count` | 有效输入计数相位 | 0 到 9 循环 |

ADC 前端向量是随机码和边界码，用来检查码制与节拍，不应呈现正弦波。

## 对称 FIR

| 变量 | 含义 | 正常关系 |
|---|---|---|
| `sample_valid` | 新的 20 MSPS 输入样点 | 在 200 MHz 域每 10 拍一次 |
| `sample_data` | 14 bit 有符号输入 | MATLAB 向量提供 |
| `active` | 当前正在计算一个 FIR 输出 | 连续输入时保持有效 |
| `phase` | 128 个对称抽头的时分相位 | 0 到 9 循环 |
| `valid_select/pair/product` | 选择、相加、乘法流水有效 | 逐级延迟一个时钟 |
| `tag_level4` | 到达加法树末端的相位标签 | 标签 9 完成一个输出 |
| `accumulator` | 10 个相位部分和的累加值 | Q17 缩放整数 |
| `final_sum` | 一个完整 255 tap 卷积和 | 下一拍舍入输出 |
| `output_valid` | FIR 输出有效 | 每个输入样点最终对应一次输出 |
| `output_data` | 16 bit Q17 舍入结果 | 与 MATLAB bit-true 值相同 |
| `input_overrun` | 输入间隔不足 10 拍 | 正常必须始终为 0 |

## 双缓冲帧采集

加载：

```tcl
source scripts/wave_g_frame.tcl
```

| 变量 | 含义 | 正常关系 |
|---|---|---|
| `capture_enable` | 允许采集新帧 | 测试期间为 1 |
| `sample_valid/data` | FIR 的 20 MSPS 输出流 | 测试中每 10 个系统时钟一个样点 |
| `decimation_count` | 20→2 MSPS 抽取相位 | 正式配置 0 到 9 |
| `write_addr` | 当前帧写地址 | 0 到 `FRAME_LENGTH-1` |
| `write_bank` | 正在写的 Bank | 每完成一帧翻转 |
| `frame_ready` | 一帧写完的单拍脉冲 | 脉冲时 `frame_bank` 有效 |
| `frame_bank` | 刚完成的是哪个 Bank | 正常连续帧为 0、1、0、1 |
| `bank_pending` | 尚未被处理器释放的帧 | 对应位在 release 后清零 |
| `read_enable/bank/addr` | FFT侧同步读请求 | BRAM读延迟一个时钟 |
| `read_data` | 读出的16 bit帧样点 | 与MATLAB抽取向量一致 |
| `release_valid/bank` | FFT处理完成并释放Bank | 允许采集端再次使用该Bank |
| `capture_stalled` | 两个Bank都未释放 | 正常处理速度下应为0 |
| `frame_overrun` | 采集数据因无空闲Bank丢失 | 正常必须始终为0 |

## Hann 加窗与 FFT 输入流

加载：

```tcl
source scripts/wave_g_fft_input.tcl
```

| 变量 | 含义 | 正常关系 |
|---|---|---|
| `start/start_bank` | 启动处理指定帧 | 仅在 `busy=0` 时接收 |
| `frame_read_enable/bank/addr` | 向帧 BRAM 发出读请求 | 地址从 0 递增至帧末 |
| `read_pending` | 等待 BRAM/窗 ROM 同步读出 | 请求后一拍有效 |
| `sample_stage` | BRAM 读出的有符号帧样点 | 十进制查看最直观 |
| `coeff_stage` | 对应的 Q15 Hann 系数 | 首尾接近 0，中间接近 32767 |
| `sample_pending` | 输入寄存器中已有待乘数据 | 将 BRAM 与 DSP 隔开以满足 200 MHz |
| `product_stage` | 样点与 Q15 系数的乘积 | 下一阶段右移 15 位并舍入 |
| `fft_valid/ready` | FFT 输入 ready/valid 握手 | 仅二者同时为 1 才消费一个点 |
| `fft_real/imag` | FFT 实部/虚部输入 | 实部为加窗结果，虚部恒为 0 |
| `fft_last` | 当前点是帧末 | 只在第 4095 点与 `fft_valid` 同时有效 |
| `release_valid/bank` | 整帧发送完成并释放 Bank | 最后一次握手后脉冲一次 |

## 端到端处理流水

启动并自动加入关键波形：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_g_pipeline_xsim.ps1 -Gui
```

在 Tcl Console 中执行：

```tcl
source scripts/wave_g_pipeline.tcl
run all
```

波形组按处理顺序排列：ADC 原始码和 `/10`、FIR、帧 `/10`、Hann/FFT 握手。
测试台故意拉低若干拍 `fft_ready`，此时 `fft_valid=1` 的 `fft_real` 和
`fft_last` 必须保持不变。最终必须看到 16 次 `fft_valid && fft_ready`、最后一点
`fft_last=1`、一次 `frame_done`，且 `adc_input_overrun`、`frame_overrun`、
`scheduler_overrun` 始终为 0。16 点只是为了让 GUI 易读；正式模块参数为 4096 点。

端到端测试的 ADC 假输入是数字码向量，不是仿真中的模拟电压源。它对应
14 bit、满量程约 2 Vpp 的量化码，主体为 460 kHz 与 1.42 MHz 双音叠加少量噪声，
开头另放入满负码、零附近和满正码等边界值，以同时检查码制、符号和流水节拍。
