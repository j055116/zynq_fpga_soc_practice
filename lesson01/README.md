# Lesson 01 — AXI4-Lite Register Slave (simulation only)

> **聲明：** 本專案內容由 AI 產生，僅供個人學習與參考。內容可能存在錯誤或疏漏，歡迎指正與交流。
>
> **Disclaimer:** The content in this project is AI-generated and intended solely for personal learning and reference. It may contain errors or omissions. Corrections and feedback are welcome.

## Scope
Pure Verilog-2005 AXI4-Lite slave and directed testbench. This is **not** a Zynq PS simulation and does not require a board.

Register map (byte addresses):

| Offset | Name | Access | Reset/value |
|---|---|---|---|
| 0x00 | CONTROL | RW | 0 |
| 0x04 | STATUS | RO | constant 1 (mock ready) |
| 0x08 | DATA | RW | 0 |

32-bit data bus, 8-bit address bus, byte strobes supported. Single outstanding write/read; AW and W buffered independently. Reserved writes ignored and reserved reads return zero with OKAY (simplified teaching policy). No accelerator attached yet.

## Run with Icarus Verilog
```bash
iverilog -g2012 -s tb_axi_lite_regs -o sim.vvp axi_lite_regs.v tb_axi_lite_regs.v
vvp sim.vvp
```
Expected final line: `ALL TESTS PASSED`. Open `wave.vcd` in GTKWave.

## Run with Vivado XSim
From Vivado Tcl Console in this folder:
```tcl
xvlog axi_lite_regs.v tb_axi_lite_regs.v
xelab tb_axi_lite_regs -s tb_sim
xsim tb_sim -runall
```
The testbench creates `wave.vcd` where the simulator runs. Use `xsim tb_sim -gui` for waveform inspection if desired.

## Architecture guide and waveform animation
Architecture guides: [English](./axi_lite_regs_ARCHITECTURE.md) | [繁體中文 / Traditional Chinese](./axi_lite_regs_ARCHITECTURE_zh-TW.md). Both document the RTL block inventory, signal paths, reset/handshake behavior, and review notes.

Open [waveform_explorer.html](./waveform_explorer.html) in a browser and select `wave.vcd`. The offline player supports play/pause, previous/next rising `ACLK` edge, edge or timestamp seeking, playback speed, signal snapshots, functional-group context, and links to source anchors. The supplied VCD uses a 1 ps timescale; the selected reference edge is `tb_axi_lite_regs.dut.ACLK` rising. The viewer reports timestamp snapshots and does not infer process execution from value changes.

## Checkpoints
- Observe VALID && READY on AW/W/AR channels.
- Check write response BVALID/BREADY and read response RVALID/RREADY.
- Check WSTRB byte masking: 0x12345678 -> 0x1234AB78.
- Verify STATUS ignores writes.

## Extended directed tests
- AW first and W first, with a six-cycle gap; check no premature B response and verify buffered payload survives input changes.
- Hold BREADY low for 12 cycles in each split write; check BVALID/BRESP and write-channel blocking, then complete the response handshake.
- Hold RREADY low for 16 cycles while writing a new value to the source register; check RVALID/RRESP/RDATA remain stable and AR is blocked, then verify the new register value.
- Launch a read and write concurrently to different addresses and verify both results. Same-address collision semantics are not tested.
- Assert reset after AW only, after W only, and with both B/R responses stalled. Check response/pending state clears after reset clock edges, no stale response returns, registers reset, and fresh transactions succeed.
- Continuous clock-edge monitors check B and R response stability during stalls. A global watchdog catches stuck transactions.

The DUT has synchronous active-low reset; these tests check reset after clock edges, not asynchronous assertion behavior. The extended run ends at 2250 ns.

## Challenges
1. Return SLVERR for unaligned or unmapped addresses (document behavior).
2. Add an AXI-controlled `start` bit and `done` status in Lesson 02.

## Limits
This is a directed testbench, not protocol compliance certification. It covers the scenarios above, but not all backpressure, concurrent traffic, reset timing, or illegal-address corner cases. Do not claim hardware validation or complete AXI compliance.
