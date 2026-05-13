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

## Communication Protocol

The host PC and FPGA exchange control and data messages over the FT601 USB data path. The protocol is packet based, so each USB transfer can be decoded by the FPGA packet layer before being routed to control registers, sample buffers, or future SDR processing blocks.

### USB Packet Structure

The USB packet format is still being defined. This section records the packet fields used by the FPGA `usb_packet_layer` and the host-side transfer tools.

| Field | Width | Description |
| --- | --- | --- |
| Packet header | TBD | Marks the start of a USB packet |
| Packet type | TBD | Identifies control, RX data, TX data, or debug packets |
| Payload length | TBD | Number of payload bytes or words following the header |
| Payload | TBD | Packet data body |
| Checksum / CRC | TBD | Optional packet integrity field |

## FPGA Framework

The FPGA code is being organized around a streaming data framework. The main design direction is to keep external device interfaces, clock-domain crossing, buffering, and future SDR processing blocks separated so that each part can be tested and replaced independently.

At the current stage, the FPGA framework is centered on the FT601 USB data path. The FT601 runs in its own FIFO bus clock domain, while the internal SDR logic is expected to run in the system clock domain. As a result, the USB path uses asynchronous FIFOs as the boundary between the FT601 interface and the rest of the FPGA design.

Planned top-level blocks:

- [x] FT601 FIFO interface logic
- [ ] AD9363 control and data interface
- [ ] Clock/reset architecture
- [ ] RX/TX sample data path
- [ ] Buffering and packet format
- [ ] Host communication protocol
- [ ] Debug and test modules

### `usb_fifo`

`usb_fifo.sv` implements the FT601-side USB streaming interface and the first clock-domain crossing layer.

The module contains two asynchronous FIFOs:

- RX FIFO: moves data from the FT601 clock domain into the `sys_clk` domain.
- TX FIFO: moves data from the `sys_clk` domain into the FT601 clock domain.

The FT601 control logic is implemented as a state machine using the following states:

- `FT601_IDLE`
- `FT601_WRITE_WAIT`
- `FT601_WRITE`
- `FT601_READ_OE`
- `FT601_READ`

The read path checks `FT601_RXF_N == 0` before reading from the FT601 and also checks that the RX FIFO is not almost full before accepting more data. This prevents the FT601 read side from pushing data into a nearly full FIFO.

The write path only starts when `FT601_TXE_N == 0` and the TX FIFO is not empty. Because the FIFO output data is valid after a read request, the state machine uses `FT601_WRITE_WAIT` to wait for `tx_fifo_valid` before driving `FT601_DATA` and asserting `FT601_WR_N`.

The FIFO control signals are kept outside of the FT601 bus-control always block. This keeps the design split into:

- FT601 bus control: `FT601_WR_N`, `FT601_RD_N`, `FT601_OE_N`, data bus direction, and byte enables.
- RX FIFO write control: captures FT601 data into the RX FIFO.
- TX FIFO read control: requests TX FIFO data and latches it before writing to the FT601.

## 📁 Repository Layout

```text
fpga-based-sdr/
|-- FPGA/          FPGA project files and RTL experiments
|-- images/        Project images and documentation assets
|-- python_test/   Host-side FT601 / D3XX Python tests
|-- FTD3XX.dll     Local FTDI D3XX runtime DLL
`-- README.md
```
