# TJC8048X270_11 最终显示、校准与板测指南

更新日期：2026-07-31

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

FPGA 发送 `xN.val=<十进制整数>`，随后三个 `0xFF`。电压四舍五入为整数 mV；
频率先四舍五入为 10 Hz 单位，因此屏幕的 `x3/x5/x7` 必须设为两位小数并标注
kHz。

| 控件 | FPGA 发送值 | 屏幕含义 |
|---|---:|---|
| `x0` | 整体复合波形 Vpp，mV | 整体 Vpp |
| `x1` | 整体真有效值，mV | 整体 Vrms |
| `x2` | 最低频分量峰值 Um，mV | 基波 Um |
| `x3` | 最低频分量频率，10 Hz/LSB | 基波 f，kHz，两位小数 |
| `x4` | 第二分量峰值 Um，mV | 谐波1 Um |
| `x5` | 第二分量频率，10 Hz/LSB | 谐波1 f，kHz，两位小数 |
| `x6` | 第三分量峰值 Um，mV | 谐波2 Um |
| `x7` | 第三分量频率，10 Hz/LSB | 谐波2 f，kHz，两位小数 |

例如真实频率 12345 Hz 会四舍五入发送 `x3.val=1235`，屏幕显示
`12.35 kHz`。不存在的分量对应幅值和频率均发送 0。Um 是正弦峰值，不是 Vpp。
整体 Vpp 来自时域 `max-min`；整体 Vrms 是各正交分量 RMS 的平方和开根号。

## 3. 四个触屏按钮

关闭按钮默认“发送键值”，在弹起事件中只保留下列单字节：

```text
b0（定标）  : printh 43
b1（单周期）: printh 31
b2（三周期）: printh 33
b3（频谱图）: printh 53
```

它们分别是 ASCII `C`、`1`、`3`、`S`。`b1/b2` 重新构建时域图，`b3` 发送最近
一帧 0～500 kHz 定性频谱。R19 发送 `x0..x7` 和当前模式的图形；没有 5 Hz 自动
刷新。模式请求在图形生成忙时会保留，因而不需要再按第二次。

## 4. s0 透明传输

每次传图先清除旧轨迹：

```text
cle s0.id,0 FF FF FF
addt s0.id,0,800 FF FF FF
```

屏幕返回 `FE` 后 FPGA 发送 800 个原始字节，再等待 `FD`。图形先复制到独立
快照 BRAM，后台更新不会撕裂当前画面；FE/FD 等待均有约 100 ms 超时，丢失握手
后状态机会自动回到空闲，不会永久卡死。

时域图只在显示支路对相邻真实样点做线性插值，数值测量仍使用原始样本。频谱把
0～500 kHz 映射到列 24～775，左右各留 24 点空白，避免边界谱线只显示一半。
两种图都自动归一化到 0～255，只作定性展示。

## 5. 现场电压校准

1. 信号源输出 100 kHz、200 mVpp、0 V offset 的纯正弦；源、线缆与 ADC 输入按
   50 Ω 条件配置，并在 ADC 输入端复核实际 Vpp。
2. 待输出稳定后点击 `b0` 一次。
3. FPGA 只接受 99～101 kHz、单分量、非零幅值的连续 16 帧，成功后更新
   Q16.16 `uV/code` 增益；失败时保留旧系数。
4. 按 R19，`x0` 应接近 200 mV，`x2` 应接近 100 mV，`x3` 应显示
   `100.00 kHz`。
5. 再用 10/20/50/100/200/300/400/500 kHz 中等幅值单音复核。若误差随频率
   稳定变化，记录为模拟链路频响，不能用反复单点校准掩盖。

校准只改变电压比例，不改变 FFT 频率。掉电后可现场重新定标。

测量结果还经过两帧稳定门：连续两帧分量数一致，且频率差不超过 1 kHz、幅值和
总 RMS 差不超过 5 mV，才更新屏幕。改频、开关通道造成的第一帧会被拒绝；等待
约 4～10 ms 后再按 R19 即可。

## 6. 精简 ILA 探针

ILA 时钟 200 MHz、深度 8192，仅保留串口屏无法解释的链路诊断量：

| Probe | RTL 信号 | 建议格式 | 含义 |
|---|---|---|---|
| `probe0[13:0]` | `fifo_dout` | Signed | ADC 跨时钟 FIFO 输出 |
| `probe1[15:0]` | `debug_fir_output_data` | Signed | 20 MSPS FIR 输出 |
| `probe2[15:0]` | `fft_real` | Signed | 2 MSPS Hann 后 FFT 输入 |
| `probe3[15:0]` | `fft_output_real` | Signed | FFT 实部 |
| `probe4[15:0]` | `fft_output_imag` | Signed | FFT 虚部 |
| `probe5[11:0]` | `fft_output_bin` | Unsigned | 当前 FFT bin |
| `probe6[31:0]` | `ila_diagnostic_control` | Binary/Hex | 握手与 sticky 错误 |

`probe6` 位定义：

| Bit | 含义 | 正常预期 |
|---:|---|---|
| 0 | ADC stream valid | 周期出现 |
| 1 | `/10` 后 ADC sample valid | 每 10 个输入出现一次 |
| 2 | FIR output valid | 跟随 20 MSPS 输入 |
| 3 / 4 / 5 | FFT input valid / ready / last | valid 与 ready 握手；帧尾 last 一拍 |
| 6 / 7 / 8 | FFT output valid / ready / last | valid 与 ready 握手；bin 4095 时 last |
| 9 | spectrum bin valid | FFT 正频率输出时出现 |
| 10 | spectrum results valid | 每帧结果脉冲 |
| 11 | frame ready | 完整采样帧就绪 |
| 12 | FFT busy | 帧处理期间为 1 |
| 13 | frame done | 每帧释放脉冲 |
| 14 | 稳定测量发布 valid | 两帧通过后出现 |
| 15 | measurement stable lock | 稳态为 1，切换首帧清零 |
| 16 | FIFO overflow sticky | 必须为 0 |
| 17 | FIFO underflow sticky | 必须为 0 |
| 18 | ADC input overrun sticky | 必须为 0 |
| 19 | frame overrun sticky | 必须为 0 |
| 20 | scheduler overrun sticky | 必须为 0 |
| 21 | FFT protocol error sticky | 必须为 0 |
| 22 | calibrator measurement overrun | 必须为 0 |
| 23 | waveform request overrun | 必须为 0 |
| 24 | spectrum display overrun | 必须为 0 |
| 25 | UART request overrun | 必须为 0 |
| 26 | UART FE/FD timeout sticky | 正常闭环必须为 0 |
| 27 | UART RX framing error sticky | 必须为 0 |
| 28 | calibration error | 正常为 0 |
| 29 | calibration busy | 定标期间为 1 |
| 30 | system reset released | 正常为 1 |
| 31 | FFT 正在输出 bin 1024 | 500 kHz 右边界检查脉冲 |

常用触发：

- 验证 500 kHz 边界：`probe6[31] == 1`，确认 `probe5 == 1024`，且随后
  `probe6[10]` 出现；
- 验证稳定门：触发 `probe6[14] == 1`，切换信号后的首帧只应看到 bit10，不应
  看到 bit14；下一致帧才发布；
- 排查错误：把 `probe6[29:16]` 设为“任意非零”触发，正常长时间运行不应命中
  sticky 错误位（校准期间 bit29 除外）。

## 7. 推荐上板顺序

1. 下载 `results/board_ila/g_board_ila.bit` 和同目录 `g_board_ila.ltx`。
2. 先测 100 kHz/200 mVpp 单音并执行 b0 校准。
3. 固定 200 mVpp 扫 10、13、50、100、300、450、490、499、500 kHz，每点连续
   按 R19 三次，数值不应依赖测试顺序。
4. 关输出、改频、开输出，等待约 1 s 再按 R19；不应显示切换过程中的伪峰。
5. 依次检查 b1、b2、b3，再从 b3 返回 b1/b2；一次按键即可切换。
6. 用任意波测试弱基波和不同相位的多分量；核对 Um、频率、总 RMS 和相位相关的
   整体 Vpp。
7. 全程监控 `probe6[28:16]`。除主动校准的 bit29 外，其余错误位应保持 0。

正式产物、WNS/WHS、资源和已知限制以 `results/board_ila/build_manifest.txt`
为准。任何 RTL、ILA、IP 或 XDC 改动后都必须重新执行
`scripts/run_g_board_ila_build.ps1`，不能沿用旧时序结论。
