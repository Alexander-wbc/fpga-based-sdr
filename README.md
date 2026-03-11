# 🚀 FPGA USB3.0 SDR  
### AD9363 + Artix-7 + FT601

A **Software Defined Radio (SDR)** platform based on **AD9363 RF transceiver**, **Xilinx Artix-7 FPGA (XC7A35T)** and **FTDI FT601 USB3.0 interface**.

This project implements a **high-speed SDR architecture fully written in RTL**.  
Baseband I/Q data from the RF front-end is streamed through the FPGA and transferred to a host PC via **USB3.0**, enabling flexible software-defined signal processing.

The system is designed for **SDR research, FPGA digital signal processing experiments, and wireless communication development**.

---

# 📡 Hardware Platform

The SDR hardware consists of three main components:

| Component | Model | Description |
|--------|--------|--------|
| RF Transceiver | **AD9363** | Wideband RF transceiver supporting TX/RX I/Q data |
| FPGA | **Xilinx Artix-7 XC7A35T (FTGG484)** | Baseband processing and data streaming |
| USB Interface | **FTDI FT601** | USB3.0 FIFO bridge for high-speed PC communication |

✨ This architecture allows **real-time streaming of RF baseband data to the host PC**.

---

# 🧠 System Architecture
        RF Signal
            │
            ▼
     +-------------+
     |   AD9363    |
     | RF Transceiver
     +-------------+
            │
       Digital I/Q
            │
            ▼
    +----------------+
    |     FPGA       |
    |   XC7A35T      |
    |                |
    |  Baseband DSP |
    |  Buffering    |
    |  Control FSM  |
    +----------------+
            │
      USB3.0 FIFO
            │
            ▼
     +-------------+
     |   FT601     |
     | USB3 Bridge |
     +-------------+
            │
            ▼
           PC
  (Python / GNU Radio)

---

# ⚙️ FPGA Architecture

The FPGA implements a **streaming SDR pipeline**.

Main RTL modules include:

| Module | Description |
|------|------|
| **AD9363 Interface** | Handles I/Q sample input/output from the RF transceiver |
| **Buffer / FIFO** | Manages high-throughput streaming data |
| **Baseband Processing** | Digital signal processing modules |
| **USB Interface** | Connects FPGA data stream to FT601 |
| **Control Logic** | FSMs controlling the entire data pipeline |

The design is implemented completely in **RTL (Verilog/SystemVerilog)**.
