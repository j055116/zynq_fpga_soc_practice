# zynq_fpga_soc_practice

> **聲明：** 本專案內容由 AI 產生，僅供個人學習與參考。內容可能存在錯誤或疏漏，歡迎指正與交流。
>
> **Disclaimer:** The content in this project is AI-generated and intended solely for personal learning and reference. It may contain errors or omissions. Corrections and feedback are welcome.

Zynq / FPGA / SoC 練習專案。

## Lessons

- [Lesson 01 — AXI4-Lite Register Slave](lesson01/README.md)
- [Lesson 01 互動動畫](lesson01/waveform_explorer.html)

## 執行 Lesson 01

在儲存庫根目錄開啟 PowerShell：

```powershell
cd lesson01
iverilog -g2012 -s tb_axi_lite_regs -o sim.vvp axi_lite_regs.v tb_axi_lite_regs.v
vvp sim.vvp
```

只有編譯成功後才執行模擬。波形與模擬執行檔由本機產生，不納入版本控制。

`.agents/skills/` 放置儲存庫共用的 Codex skills。
