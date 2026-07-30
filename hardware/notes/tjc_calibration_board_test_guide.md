# TJC8048X270_11 最终显示、校准与板测指南

更新日期：2026-07-30  
目标器件：Mizar Z7 / `xc7z020clg400-2`  
串口：115200 baud、8-N-1
屏幕：TJC8048X270_11，单个波形控件 `s0`，800×256

## 1. 接线与电气安全

```text
FPGA W18 / uart_tx  -> TJC RX
FPGA W19 / uart_rx  <- TJC TX
FPGA GND            -- TJC GND
```

W18、W19 均约束为 `LVCMOS33`。连接屏幕 TX 到 W19 前，应实测其空闲高电平约
3.3 V；不能把 5 V 串口电平直接送入 Zynq。R19 是低有效 PL KEY1，RTL 内有
20 ms 消抖；一次短按只发送一次完整页面，长按不连发。

## 2. 数值控件对应关系

FPGA 发送 `xN.val=<十进制整数>`，随后三个 `0xFF`。电压已四舍五入为整数 mV；
频率发送整数 Hz，屏幕虚拟浮点控件设 3 位小数并标注 kHz。

| 控件 | FPGA 发送值 | 屏幕含义 |
|---|---:|---|
| `x0` | 整体复合波形 Vpp，mV | 整体 Vpp |
| `x1` | 整体真有效值，mV | 整体 Vrms |
| `x2` | 基波峰值 Um，mV | 基波 Um |
| `x3` | 基波频率，Hz | 基波 f，显示 kHz |
| `x4` | 谐波1峰值 Um，mV | 谐波1 Um |
| `x5` | 谐波1频率，Hz | 谐波1 f，显示 kHz |
| `x6` | 谐波2峰值 Um，mV | 谐波2 Um |
| `x7` | 谐波2频率，Hz | 谐波2 f，显示 kHz |

例如 `x3.val=12345` 显示为 `12.345 kHz`；不存在的分量对应幅值和频率均发送 0。
Um 是正弦峰 值，不是 Vpp。整体 Vpp 来自 20 MSPS 时域样本的 `max-min`，所以
不会错误地把不同初相位的三个分量 Vpp 相加；整体 Vrms 则由各正交分量 RMS
平方和开根号得到。

## 3. 四个按钮的弹起事件

关闭按钮默认“发送键值”，只保留以下单字节 `printh`：

```text
b0（定标）:  printh 43
b1（单周期）: printh 31
b2（三周期）: printh 33
b3（频谱图）: printh 53
```

含义分别是 ASCII `C`、`1`、`3`、`S`。`b1/b2` 触发 FPGA 重新构建时域图后
发送，`b3` 发送最近一帧 0–500 kHz 正频谱图。R19 则发送 `x0..x7` 和当前所选
图形。没有 5 Hz 自动刷新。

## 4. s0 透明传输协议

FPGA 先发送：

```text
addt s0.id,0,800 FF FF FF
```

等待屏幕返回 `FE` 后发送 800 个原始字节，再等待 `FD`。UART 内部先把图形复制
到独立快照 BRAM，所以后台产生新频谱不会撕裂正在发送的图。时域图把当前范围
归一化到 0–255，横向严格覆盖基波 1 周期或 3 周期；频谱横轴 0–500 kHz，800
列对 1025 个 FFT bin 做最大值合并，纵轴为相对幅度，仅作定性显示。

## 5. 现场电压校准

1. 信号源输出 100 kHz、200 mVpp、0 V offset 的纯正弦，端口与线缆按 50 Ω
   条件配置，并在 ADC 输入端复核实际 Vpp。
2. 待频率和幅值稳定后点击 `b0` 一次。
3. FPGA 只接受 99–101 kHz、单分量、非零幅值的连续 16 帧；成功后更新
   Q16.16 `uV/code` 增益。失败会保留旧系数。
4. 按 R19，`x0` 应接近 200 mV，`x3` 应显示 100.000 kHz。
5. 再用 10/20/50/100/200/300/400/500 kHz 中等幅值单音复核。若误差随频率
   稳定变化，需要后续模拟频响校正表 `K(f)`，不能用反复单点校准掩盖。

校准仅改变电压比例，不改变 FFT 频率。掉电后可以现场重新定标，当前不依赖非易失
存储。

## 6. 精简 ILA 探针

ILA 时钟 200 MHz、深度 2048。仅保留 7 个探针：

| Probe | RTL 信号 | 建议格式 | 含义 |
|---|---|---|---|
| `probe0[23:0]` | `total_vpp_uv` | Unsigned | 整体 Vpp，uV |
| `probe1[23:0]` | `total_true_rms_uv` | Unsigned | 整体真 RMS，uV |
| `probe2[19:0]` | `component0_frequency_hz` | Unsigned | 基波频率，Hz |
| `probe3[23:0]` | `component0_amplitude_uv` | Unsigned | 基波 Um，uV |
| `probe4[19:0]` | `component1_frequency_hz` | Unsigned | 谐波1频率，Hz |
| `probe5[23:0]` | `component1_amplitude_uv` | Unsigned | 谐波1 Um，uV |
| `probe6[15:0]` | `ila_measurement_control` | Binary/Hex | 状态与错误摘要 |

`probe6` 位定义：

| Bit | 含义 | 正常预期 |
|---:|---|---|
| 0 | `total_vpp_valid` | 新 Vpp 一拍脉冲 |
| 1 | `measurement_valid` | 新 FFT 测量一拍脉冲 |
| 2 | `calibration_busy` | 校准时为 1 |
| 3 | `calibration_done` | 校准成功一拍脉冲 |
| 4 | `calibration_error` | 正常为 0 |
| 5 | R19 消抖后按下脉冲 | 按键时一拍 |
| 6 | UART/透明传输忙 | 发送期间为 1 |
| 7 | 完整传输完成脉冲 | 收到 FD 后一拍 |
| 8 | FE/FD 超时粘滞位 | 正常为 0 |
| 9 | 测量/显示/UART/RX 任一错误 | 正常为 0 |
| 11:10 | 有效分量数 | 1–3 |
| 12 | 当前为频谱模式 | `b3` 后为 1 |
| 13 | 当前为三周期模式 | `b2` 后为 1 |
| 14 | FFT 协议错误摘要 | 正常为 0 |
| 15 | 系统复位已释放 | 正常为 1 |

建议以 `probe6[1]==1` 检查 FFT 数值，以 `probe6[0]==1` 检查整体 Vpp，以
`probe6[3]==1` 检查校准完成，以 `probe6[7]==1` 检查一次屏幕传输闭环。

## 7. 上板顺序

1. 下载 `results/board_ila/g_board_ila.bit` 与同目录 `.ltx`。
2. 先只接 FPGA TX、屏幕 RX 和共地，按 R19 验证数值与 800 点图。
3. 实测屏幕 TX 电平后再接 W19，依次测试 b1、b2、b3。
4. 用 100 kHz/200 mVpp 完成 b0 校准。
5. 用不同初相位的二/三分量任意波测试分离；无需外部模拟加法器。
6. 全程要求 `probe6[9]`、`probe6[14]` 和 `probe6[8]` 保持 0。

正式构建产物、WNS/WHS、资源及限制以
`results/board_ila/build_manifest.txt` 为准；任何 RTL/ILA 改动后都必须重新执行
`scripts/run_g_board_ila_build.ps1`，不能沿用旧时序结论。
