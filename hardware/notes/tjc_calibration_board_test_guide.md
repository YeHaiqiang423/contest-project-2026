# TJC4827T143 校准与二次谐波板测指南

更新日期：2026-07-30  
目标器件：Mizar Z7 / `xc7z020clg400-2`  
串口：115200 baud、8 data bits、no parity、1 stop bit

## 0. 本次构建产物

- Bitstream：`results/board_ila/g_board_ila.bit`
- Probe：`results/board_ila/g_board_ila.ltx`
- 构建清单：`results/board_ila/build_manifest.txt`
- Vivado：2020.2
- 器件：`xc7z020clg400-2`
- 最终时序：WNS `+0.016 ns`、WHS `+0.034 ns`、TNS/THS均为0
- 资源：6521 LUT、11906 FF、29 BRAM tile、35 DSP
- DRC：Error 0、Critical Warning 0
- 未约束内部端点：0

SHA-256：

```text
g_board_ila.bit  747EE86CC430857EE5B62DC9DEB605F88F14B16E33EEADA988BEED8FD9CF1E93
g_board_ila.ltx  4F570AB4CA480CA1A961FA7A7339FDA13AD9092B218ADB3D4B92CD8D49E11704
```

路由裕量只有 `+0.016 ns`，虽然满足正式门禁，但后续任何RTL或ILA改动都必须重新
执行完整实现，不能沿用本次时序结论。

## 1. 接线与电气安全

```text
FPGA W18 / uart_tx  -> TJC RX
FPGA W19 / uart_rx  <- TJC TX
FPGA GND            -- TJC GND
```

W18、W19 的 FPGA 约束均为 `LVCMOS33`。在连接 TJC TX 到 W19 前，必须实测
TJC TX 空闲高电平约为 3.3 V，或在中间加入可靠电平转换。不可把 5 V 串口输出
直接送入 Zynq LVCMOS33 输入。淘晶驰官方连接资料也提醒部分系列存在 5 V 串口
输出，不能只根据接口名称判断电平。

R19 是 Mizar Z7 的 PL KEY1。原理图确认该按键外部上拉、按下接地，RTL按低有效
处理，并要求连续稳定 20 ms 才产生一次发送脉冲；长按不会重复发送。

## 2. 串口屏工程设置

四个虚拟浮点数控件：

| 控件 | FPGA发送值 | 屏幕显示设置 | 含义 |
|---|---:|---|---|
| `x0` | 整数 mVpp | 0位小数 | 基波 Vpp |
| `x2` | 整数 Hz | 3位小数、单位 kHz | 基波频率 |
| `x3` | 整数 mVpp | 0位小数 | 第二个频率分量 Vpp |
| `x4` | 整数 Hz | 3位小数、单位 kHz | 第二个频率分量频率 |

例如 FPGA 发送 `x2.val=12345`，控件显示 `12.345 kHz`；发送
`x2.val=12000`，显示 `12.000 kHz`。

校准按钮的“弹起事件”只写一行：

```text
printh 43
```

即向 FPGA 发送一个 ASCII `C`（`0x43`）字节。FPGA 收到后固定以
`200000 uVpp` 为参考，平均随后16个有效单音帧进行校准。正常显示命令由 FPGA
按陶晶驰格式发送，例如：

```text
x0.val=200 FF FF FF
x2.val=100000 FF FF FF
x3.val=50 FF FF FF
x4.val=200000 FF FF FF
```

上面的空格只用于文档分隔，实际发送内容是ASCII字符串紧接三个 `0xFF`。

屏幕不会周期刷新。每次短按板载 R19，FPGA才把最近一次完整测量结果发送给四个
控件。这样可以在信号稳定后人工取数，也避免串口刷新干扰观察。

## 3. 现场校准步骤

1. 信号源和电缆都按50 ohm条件工作，输入纯净正弦：
   `100 kHz、200 mVpp、0 V offset`。
2. 等待波形稳定，点击屏幕校准按钮一次。
3. ILA用 `ila_measurement_control[5]==1` 可确认屏幕命令已收到。
4. 校准期间 bit2 为1；结束时 bit3脉冲，并要求 bit4为0。
5. 短按 R19 一次发送新结果；`x0` 应接近200，`x2` 应显示
   `100.000 kHz`。
6. 在50、100、200、300、500 kHz复核单音幅值。若随频率出现稳定偏差，属于
   模拟前端频响，应加入 `K(f)` 表，不能反复用单点增益掩盖。

自动校准只接受16个连续单音帧。任一帧被判为多分量或峰值为0，校准失败并保留
原增益。

## 4. 二次谐波测试

推荐用任意波形输出：

```text
s(t) = 80 mV*sin(2*pi*100 kHz*t)
     + 20 mV*sin(2*pi*200 kHz*t+phi)
```

其中 `phi` 可任意。预期分量结果为：

```text
x0 = 160        // 基波160 mVpp
x2 = 100000     // 显示100.000 kHz
x3 = 40         // 二次谐波40 mVpp
x4 = 200000     // 显示200.000 kHz
```

频谱用复数模长检测，因此二次谐波相位不必与基波相同。测试时仍需确保任意波发生器
显示的总Vpp定义、50 ohm负载设置和实际BNC端电压一致。若只有单通道任意波输出，
直接在波形文件中合成两项即可，不需要外部模拟加法器。

## 5. 精简ILA探针

ILA时钟200 MHz、深度4096。新版仅有9个探针：

| Probe | 信号 | 显示格式 | 含义 |
|---|---|---|---|
| `probe0[13:0]` | `fifo_dout` | Signed Decimal/Analog | ADC原始二补码 |
| `probe1[1:0]` | `measurement_component_count` | Unsigned | 有效分量数 |
| `probe2[19:0]` | `component0_frequency_hz` | Unsigned | 基波频率Hz |
| `probe3[23:0]` | `component0_amplitude_uv` | Unsigned | 基波峰值uV |
| `probe4[19:0]` | `component1_frequency_hz` | Unsigned | 第二分量频率Hz |
| `probe5[23:0]` | `component1_amplitude_uv` | Unsigned | 第二分量峰值uV |
| `probe6[23:0]` | `total_true_rms_uv` | Unsigned | 总真有效值uV |
| `probe7[23:0]` | `calibration_gain_q16` | Unsigned/Hex | Q16.16 uV/code增益 |
| `probe8[15:0]` | `ila_measurement_control` | Binary/Hex | 校准、UART和健康状态 |

`probe8` 位定义：

| Bit | 含义 | 正常值/用途 |
|---:|---|---|
| 0 | `measurement_valid` | 结果更新触发 |
| 1 | `spectrum_results_valid` | 原频谱结果脉冲 |
| 2 | `calibration_busy` | 校准中为1 |
| 3 | `calibration_done` | 校准完成一拍脉冲 |
| 4 | `calibration_error` | 正常为0 |
| 5 | `uart_rx_calibrate_command` | 收到屏幕 `0x43` 一拍脉冲 |
| 6 | `uart_send_button_pressed` | R19消抖后按下一拍脉冲 |
| 7 | `uart_tx_busy` | 四条命令发送期间为1 |
| 8 | `measurement_overrun` | 正常为0 |
| 9 | `uart_rx_framing_error_sticky` | 正常为0 |
| 10 | `fft_configured` | 正常为1 |
| 11 | `fft_protocol_error` | 正常为0 |
| 12 | `fifo_empty` | 稳态通常为0 |
| 13 | ADC FIFO overflow sticky | 正常为0 |
| 14 | FIFO underflow | 正常为0 |
| 15 | `system_rst_n` | 正常为1 |

结果检查用 `probe8[0]==1` 触发；校准完成用 `probe8[3]==1` 触发；R19发送用
`probe8[6]==1` 触发。校准后：

```text
x0应等于 round(2*probe3/1000)
x2应等于 probe2
x3应等于 round(2*probe5/1000)
x4应等于 probe4
```

## 6. 建议的首次上板顺序

1. 先只连接 FPGA TX、屏幕 RX和共地，不接屏幕 TX；下载 `.bit/.ltx`。
2. 输入100 kHz、200 mVpp单音，按R19，确认 `x0/x2` 能显示，证明发送方向和
   115200波特率正确。
3. 测量屏幕 TX 空闲高电平。确认约3.3 V或加入电平转换后，再接W19。
4. 点击屏幕校准按钮，ILA以 `probe8[5]==1` 验证 `0x43` 已收到，再以
   `probe8[3]==1` 验证校准完成且 bit4为0。
5. 按R19更新显示，随后进行本指南的二次谐波测试。

