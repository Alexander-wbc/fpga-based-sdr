# FPGA-Based SDR

An FPGA-based software-defined radio platform built around:

- 📡 RF transceiver: `AD9363`
- 🔧 FPGA: `Xilinx Artix-7`
- 🔌 USB interface: `FTDI FT601`

The project goal is to build a compact SDR hardware and FPGA platform capable of moving baseband data between the AD9363, the FPGA fabric, and a host PC over USB.

## 📷 Hardware

![PCB test setup](images/PCB_test_1.jpg)

The hardware is designed as a direct RF-to-host SDR signal chain. The AD9363 handles RF transmit/receive conversion and provides digital I/Q sample data to the FPGA. The Artix-7 FPGA is the central device on the board: it is responsible for clock-domain handling, buffering, control logic, future baseband processing, and moving sample data between the RF front-end and the USB interface.

The FT601 is used as the high-speed USB bridge between the FPGA and the host PC. On the FPGA side, it exposes a parallel FIFO-style interface, which makes it suitable for streaming large blocks of baseband data without requiring a full USB stack inside the FPGA logic. On the host side, the FTDI D3XX driver is used for device enumeration, connection testing, and future data transfer tools.

The current PCB integrates the main SDR devices, power supplies, FPGA configuration circuit, USB interface, and board-level routing required for early bring-up. The first hardware revision has already been assembled, and the FT601-to-FPGA path has been validated at a basic communication level. The next hardware revision will focus on fixing the FPGA bank power planning and improving the FT601 USB 3.0 link behavior.

| Block | Device | Role |
| --- | --- | --- |
| RF front-end | `AD9363` | RF transmit/receive conversion and digital I/Q interface |
| Digital logic | `Xilinx Artix-7` | Data buffering, control logic, FPGA-side SDR processing |
| USB bridge | `FTDI FT601` | Parallel FIFO interface between FPGA and host PC |
| Configuration | External Flash | FPGA bitstream storage, currently affected by bank power planning |

## 🎯 Architecture

The main hardware direction is still:

```text
Artix-7 + AD9363 + FT601
```

## ✅ Project Roadmap

- [x] Complete BGA soldering for the FPGA-side hardware
- [x] Bring up the FT601 device on the host side
- [x] Complete basic FT601-to-FPGA communication testing
- [x] Add Python test code for FT601 / D3XX device detection
- [ ] Debug FT601 USB 3.0 SuperSpeed operation
- [ ] Test and bring up the AD9363
- [ ] Start writing the FPGA RTL for the SDR data path
- [ ] Update the schematic based on the current hardware issues
- [ ] Rework the FPGA bank power plan and Flash connection
- [ ] Continue system-level SDR validation

## ⚠️ Current Issues

### 🔌 FT601 Link Speed

The FT601 can currently enumerate and work only in USB 2.0 mode.

Expected behavior is USB 3.0 SuperSpeed operation, so this still needs further debugging. Possible areas to check include USB 3.0 routing, connector signal integrity, cable quality, FT601 configuration, and host-side driver/device recognition.

### ⚡ FPGA Bank Power Planning

The FPGA bank power planning is not ideal in the current hardware revision.

This affects the external Flash interface, and the Flash cannot work correctly with the present bank/power arrangement. The schematic and bank assignment need to be revised in the next hardware update.

## 🧠 FPGA Program Design

This section is reserved for the FPGA design notes.

Planned content:

- [ ] FT601 FIFO interface logic
- [ ] AD9363 control and data interface
- [ ] Clock/reset architecture
- [ ] RX/TX sample data path
- [ ] Buffering and packet format
- [ ] Host communication protocol
- [ ] Debug and test modules

## 📁 Repository Layout

```text
fpga-based-sdr/
|-- FPGA/          FPGA project files and RTL experiments
|-- images/        Project images and documentation assets
|-- python_test/   Host-side FT601 / D3XX Python tests
|-- FTD3XX.dll     Local FTDI D3XX runtime DLL
`-- README.md
```
