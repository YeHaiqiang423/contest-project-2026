# Codex 项目规则

## 项目上下文

- 全国大学生电子设计竞赛 FPGA 项目。
- 开发板为 Mizar Z7，当前目标器件按资料和参考工程暂定 `xc7z020clg400-2`。
- 数据转换链路包含 ADS6149 ADC（实物丝印已确认）和 DAC5688 DAC；DAC 配置参考工程使用 STM32F103。
- 本机使用 MATLAB R2024b 与 Vivado/XSim 2020.2。
- `docs/` 中的 FPGA 回环参考工程由 Vivado 2025.2 生成，与本机版本不一致。

## 开工前

- 先阅读 `README.md`、顶层模块和当前任务涉及的约束或接口文档。
- 可只读查阅 `docs/`，但不要修改、移动、删除或提交其中的厂商资料。
- 不猜测板卡型号、芯片引脚、接口电平、采样时钟或器件时序；资料冲突时明确指出。
- 不修改系统环境变量、软件安装或全局 VS Code 设置，除非用户明确授权。

## 源码与工具协作

- VS Code、MATLAB 和 Vivado 必须引用本仓库中的同一份源码，不创建互相分叉的副本。
- Vivado 工程应引用 `rtl/src/`、`rtl/tb/`、`rtl/constraints/`；工程生成目录不得作为源码来源。
- 不用 Vivado 2020.2 直接打开并保存 2025.2 厂商参考工程。需要复用时，仅提取 RTL/XDC/IP 参数，并在 2020.2 中重建或重新生成 IP。
- MATLAB 黄金模型与 RTL 使用相同测试向量，输入和期望输出放在 `matlab/vectors/`。
- 生成文件、波形和报告放入 `logs/` 或 `results/`，不要混入源码目录。

## 用户的正式工具流

- VS Code 是唯一的日常代码编辑入口，也用于 Git 提交、拉取和推送；不要要求用户在 Vivado 或 MATLAB Editor 中重复维护源码。
- MATLAB 用于浮点模型、定点化、测试向量和黄金输出；MATLAB 扩展已安装，项目配置采用按需启动以减少内存占用。
- Vivado GUI 由用户负责查看工程状态、综合/实现报错、时序、器件视图、Hardware Manager 和最终下载。
- Codex 可以在后台调用 MATLAB、XSim 和 Vivado batch/Tcl 完成向量生成、自动仿真、综合、实现、报告检查和 bitstream 生成，但必须遵守下方 bitstream 门禁。
- Vivado 工程添加源码时必须引用仓库原文件，不勾选 `Copy sources into project`。Design Sources 指向 `rtl/src/`，Simulation Sources 指向 `rtl/tb/`，Constraints 指向 `rtl/constraints/`。
- IP 后续通过 Tcl 创建或按 Vivado 版本重建；不要提交跨版本生成目录，不依赖手工复制的 IP 输出文件。
- 推荐流程：MATLAB 模型 -> 定点模型 -> 导出向量/黄金输出 -> RTL -> 自检 Testbench/XSim -> 综合 -> 实现 -> DRC/时序检查 -> bitstream -> 用户在 Hardware Manager 下载。
- 当前仓库提供的 `sat_gain` 仅是无 IP 工具链自检样例，不是最终板级设计。

## Verilog 与 SystemVerilog 策略

- 团队可能有成员只使用 Verilog。默认优先选择易协作的 Verilog-2001 可综合子集编写正式 RTL，文件后缀使用 `.v`。
- Testbench 可以使用 SystemVerilog `.sv`，以便进行文件读写、自检、断言和更清晰的数据类型处理。
- Vivado 工程允许 `.v` 与 `.sv` 混合；Verilog 模块和 SystemVerilog 模块可以互相实例化，但端口必须使用双方兼容的简单类型。
- SystemVerilog 是 Verilog 的超集，但兼容不是双向的。包含 `logic`、`always_comb`、`always_ff`、`interface`、`struct`、class、`.*` 等语法的文件不能仅通过改后缀变成 Verilog。
- 除非团队明确同意，正式 RTL 接口避免 `interface`、复杂结构体、class、UVM 和依赖特定工具的新语法。
- 若现有 `.sv` RTL 需要交给只用 Verilog 的队友，先明确要求并进行语法转换与重新仿真，不能直接改名为 `.v`。

## 仿真与波形

- 默认先运行自检 Testbench；仅看到波形正常不能代替自动比对。
- 当前自检入口为 `scripts/run_xsim.ps1`，成功标志为日志中的 `PASS`。
- 用户查看波形时，优先在 Vivado 中选择 `Run Simulation -> Run Behavioral Simulation`，将 Testbench 设为 Simulation Top。
- 波形中至少观察时钟、复位、输入/输出有效信号、数据、状态机状态和关键流水线中间量；有符号数据设置为 `Signed Decimal`，定点数据注明 Q 格式。
- 需要后台生成波形时，可使用 XSim Tcl 记录 WDB/VCD，并把结果放入 `results/`；不要把波形文件提交 Git。
- 仿真完成必须记录测试数量、错误数、首个错误位置、延迟和是否出现 X/Z。

## RTL 规则

- RTL 必须可综合；避免综合源码中的不可综合延时及仅仿真结构。
- 时序逻辑使用非阻塞赋值，组合逻辑避免锁存器。
- 明确复位极性、同步/异步方式、时钟域和跨时钟域处理。
- 算法移植前明确位宽、符号、Q 格式、舍入、截断、饱和及溢出策略。
- 修改 XDC 前说明依据，并核对顶层端口、管脚、电压标准和 `create_clock`。
- 不自动下载 bitstream 到开发板；Hardware Manager 下载始终由用户执行，除非用户针对某次下载明确授权。

## 实现与 bitstream 门禁

- 综合成功不等于可以上板。允许在接口和管脚未定版时做纯 RTL 综合，但必须明确标注“未使用板级约束”。
- 运行布局布线前必须具备可信顶层模块、时钟/复位定义和 XDC；不得让 Vivado 任意分配板级管脚。
- 生成 bitstream 前必须逐项确认：目标器件、板卡版本、顶层端口、所有外部 IO 管脚、IOSTANDARD、时钟管脚与周期、复位极性、ADC/DAC 接线和相关跳线。
- 存在 `UCIO-1`、`NSTD-1`、未约束时钟、严重 CDC、关键 DRC、负 WNS/TNS 或用户未确认的管脚时，不得通过降低 DRC 等级或强制绕过来生成“可下载”bitstream。
- 可以由 Codex 后台执行 `synth_design`、`opt_design`、`place_design`、`phys_opt_design`、`route_design`、`report_drc`、`report_timing_summary` 和 `write_bitstream`。
- 后台生成 bitstream 后必须同时交付并总结：`.bit`、可选 `.ltx`、Vivado 版本、Git 提交号、目标器件、约束来源、DRC、WNS/TNS、资源占用和所有关键警告。
- bitstream 与生成报告放在 `results/`，默认由 `.gitignore` 排除；不能把未验证 bitstream 描述为可安全上板。

## 验证与完成标准

- MATLAB 浮点模型应可重复运行，定点模型误差应按题目指标量化。
- MATLAB 应能导出确定的输入向量和黄金输出。
- RTL 应配套自检 Testbench，并覆盖复位、正常输入、边界值、溢出和连续数据。
- 仿真除通过/失败外，还需检查数值误差、X/Z、延迟和吞吐率。
- 综合需检查关键警告；实现后记录 WNS/TNS、资源占用和目标时钟。
- 每次报告验证结果时列出实际执行的命令；未运行的验证必须明确标注。
- 大改动前保留当前可验证状态，不覆盖用户已有或已验证修改。
- 当前已验证基线：MATLAB R2024b 成功生成 64 组 `sat_gain` 向量；XSim 2020.2 自检 64/64 通过；对 `xc7z020clg400-2` 综合为 0 error、0 critical warning、0 warning。该基线没有板级 XDC，也未执行实现和 bitstream。

## 硬件认知与当前限制

- 已知硬件：Mizar Z7、Zynq `xc7z020clg400-2`、ADS6149 ADC、DAC5688 DAC，以及 STM32F103 DAC 配置参考例程。
- 已有资料：Mizar Z7 Rev.1.1 用户手册、原理图、尺寸资料、7Z020 通用 XDC、ADS6148/DAC5688 数据手册、硬件设计文件和 ADC/DAC 回环参考工程。
- 当前仍未定版：ADC/DAC 转接板到 Mizar Z7 的实际接线、各数据/控制管脚、采样与系统时钟来源、IO 电压标准、复位/使能极性、最终顶层端口和跳线状态。
- 硬件信息缺失时可以继续算法、接口抽象和纯 RTL 验证，但不得猜测管脚或宣称具备可上板条件。

## Git 规则

- `docs/` 永远不纳入 Git，也不要用强制添加绕过忽略规则。
- 不提交 Vivado 缓存、运行目录、日志、波形、bitstream 或 MATLAB 自动生成文件。
- 提交前运行 `git status --ignored`，确认没有硬件资料或生成物进入暂存区。
- 未经用户明确授权，不创建远程仓库、不推送、不改变 GitHub 仓库可见性。
- 当前远程仓库为 `https://github.com/YeHaiqiang423/contest-project-2026.git`，默认分支为 `main`。
- GitHub CLI 不是必需工具；VS Code 内置 Git/GitHub 登录或 Git Credential Manager 均可完成推送。
- 提交前查看 `git status` 和 diff；推送属于外部写入，只有用户明确要求时执行。

## 新对话接手流程

- 用户会在正式电赛时新开项目对话。新对话中的 Codex 必须首先完整阅读本文件和 `README.md`，然后查看 `git status --short --branch`，不得从记忆猜测项目状态。
- 随后清点 `docs/` 中新增的赛题、板卡和器件资料，只读取当前任务相关内容；`docs/` 始终保持不入库。
- 开赛拿到题目后，先从题目提取可量化指标、接口、输入范围、采样率、实时性、评分点和硬件限制，更新 README 的题目与总体方案，再开始写代码。
- 在修改前确认当前顶层、目标器件、时钟、复位、数据格式和验证方法；信息缺失时列出缺口并继续能安全推进的模型或接口工作。
- 优先建立最短闭环：小规模 MATLAB 黄金模型 -> 少量确定性向量 -> RTL 自检 -> 综合，再逐步扩展性能和板级功能。
- 每个阶段都保留一条可重复命令或 Tcl 脚本，避免只能通过 GUI 手工复现。
- 不重复安装或修改工具。已知路径有效时直接使用；仅在调用失败后做只读诊断。

## 工具路径

- MATLAB：`G:\Matlab\bin\matlab.exe`
- Vivado：`D:\XUni\Vivado\2020.2\bin\unwrapped\win64.o\vivado.exe`
- XSim：`D:\XUni\Vivado\2020.2\bin\unwrapped\win64.o\xsim.exe`
- Git：`D:\Git\cmd\git.exe`
- Vivado 标准批处理入口：`D:\XUni\Vivado\2020.2\bin\vivado.bat`
- XSim 工具链入口：`D:\XUni\Vivado\2020.2\bin\xvlog.bat`、`xelab.bat`、`xsim.bat`
- VS Code：已安装 MathWorks MATLAB、Verilog HDL、TerosHDL 和 WaveTrace 扩展。
