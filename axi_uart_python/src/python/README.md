# **High-Performance UART-to-AXI4 Memory Staging Subsystem**

## **System Technical Documentation & Specification Manual**

This document provides a comprehensive architecture and operational overview of the parameterized **UART-to-AXI4 Full Memory Staging Subsystem**. This framework bridges low-speed asynchronous serial peripherals (operating at **115200 Baud**) with high-speed memory-mapped AXI4 system buses (operating at **80 MHz**) without blocking or stalling the target system fabric.

## **1\. Subsystem Architecture Overview**

Directly interfacing a slow serial link with an active AXI interconnect creates an architectural bottleneck: holding an AXI transaction lane open while waiting milliseconds for sequential serial bytes to crawl over a physical wire will deadlock high-frequency system buses.

To isolate these distinct clock domains, this system utilizes a **Staging Buffer Architecture**.

The hardware fabric is split into two primary operational execution layers:

1. **The Asynchronous I/O Layer (Port A Domain):** Runs at slow serial speeds. Data bytes are gathered from or pushed to the physical UART lines and staged sequentially inside a **2KB True Dual-Port Block RAM**.  
2. **The High-Speed Co-Processing Layer (Port B Domain):** Runs at full fabric frequency (**80 MHz**). Once an entire data packet is compiled inside the staging RAM (for writes) or requested from memory (for reads), a dedicated **AXI4 Full Master Data Mover** claims the bus and streams the data block in a single high-speed hardware burst.

## **2\. Hardware Micro-Architecture (Verilog Fabric)**

The hardware infrastructure consists of seven core functional modules integrated within a point-to-point data topology.

### **Interconnect Top-Level Layer (`fpga_top.v`)**

The structural top-level module maps out system nets, handles reset conditioning rules, and instantiates the physical macros. It establishes a strict reset control tree: the entire fabric reset line (`sys_rst_n`) is held asserted low until the board reset pin is de-asserted **and** the internal PLL stabilizes its clock phases and pulls its lock pin high.

### **Clock Management Unit (`FCCC_C0`)**

A physical hardware macro mapping directly to the **SmartFusion2/RTG4 Fabric Clock Control Center (FCCC)**. It ingests an external **50 MHz** crystal oscillator source and synthesizes a low-jitter global global clock branch at **80 MHz** to drive the internal processing logic.

### **Asynchronous Line Receivers/Transmitters (`uart_rx.v` / `uart_tx.v`)**

* **`uart_rx`:** Utilizes a **16x oversampling clock divider** architecture to eliminate line noise and jitter. Incoming data is passed through a dual-stage register pipeline to mitigate metastability before checking start-bit center validation at sample count 7\.  
* **`uart_tx`:** A straightforward parallel-to-serial shift register. It captures 8-bit bytes from the internal control logic and automatically appends low start bits and high stop bits using clean bit-period duration windows.

### **True Dual-Port Staging RAM (`ram_2k_true_dual_port.v`)**

A dedicated dual-clock/dual-access **2KB Block RAM configuration (256 entries deep × 64 bits wide)**. It utilizes the `(* ramstyle = "block" *)` synthesis compiler directive to force Libero to instantiate physical LSRAM modules rather than eating up fabric flip-flops. It operates with a **Read-First / Old-Data** access pattern to avoid internal bus racing conditions during simultaneous lookahead operations.

```
       PORT A (UART FSM Domain)                PORT B (AXI Master Domain)
 ┌───────────────────────────────────┐   ┌───────────────────────────────────┐
 │ ram_a_we    [1-bit]               │   │ ram_b_we    [1-bit]               │
 │ ram_a_waddr [8-bit]               │   │ ram_b_addr  [8-bit]               │
 │ ram_a_wdata [64-bit Input]        │   │ ram_b_wdata [64-bit Input]        │
 │ ram_a_raddr [8-bit]               │   │                                   │
 │ ram_a_rdata [64-bit Output]       │   │ ram_b_rdata [64-bit Output]       │
 └─────────────────┬─────────────────┘   └─────────────────┬─────────────────┘
                   │                                       │
                   └───────────────►[2KB LSRAM]◄───────────┘
```

### **Protocol Handshake Controller (`system_control_fsm.v`)**

A central command state machine utilizing a **5-bit wide state register** to handle 17 distinct operational execution phases without bit-width truncation crashes. It handles the low-level serialization/deserialization logic, tracks data beat progression indices, and orchestrates the launch triggers for the high-speed data mover.

### **AXI4 Full Master Data Mover (`axi4_master_data_mover.v`)**

A high-throughput bus master controller. It directly handles standard AXI4 Full transactions, including address phase handshaking (`xVALID` / `xREADY`), continuous burst beat loops, byte-lane strobe generation (`m_axi_wstrb = 8'hFF`), and transaction envelope boundary termination flag management (`m_axi_wlast` / `m_axi_rlast`).

## **3\. Communication Protocol & FSM States**

The link between the host Python software and the FPGA hardware is built around a deterministic, closed-loop byte-token handshake sequence. Every phase must be acknowledged by the hardware before the host software can proceed to the next step.

### **The 4-Phase Handshake Protocol Matrix**

| Step | Direction | Data Packet Passed | Expected Return Token | Target Hardware Action |
| ----- | ----- | ----- | ----- | ----- |
| **1\. Opcode** | Host → FPGA | 1 Byte (`0x31` \- `0x34`) | **`'a'`** (`0x61`) | Validates transaction mode, chooses path, resets indices. |
| **2\. Address** | Host → FPGA | 4 Bytes (Big-Endian) | **`'d'`** (`0x64`) | Latches 32-bit destination offset; maps local RAM indexing. |
| **3\. Length** | Host → FPGA | 2 Bytes (Big-Endian) | **`'l'`** (`0x6C`) | *Burst Only.* Latches total 64-bit word count constraints. |
| **4\. Payload** | Host ↔ FPGA | Stream Data Block | **`'c'`** (`0x63`) | *Burst Reads Only.* Signals that the AXI memory fetch has filled the buffer. |

### **Finite State Machine Flow Diagram**

### **Specialized Functional Refactors**

#### **Single-Transaction AXI Upscaling**

To maximize logic reuse and ensure clean bus diagnostics, **Single Write (`0x31`)** and **Single Read (`0x32`)** operations are structurally intercepted during the Phase 2 address-latch window. The FSM forces `len_buffer <= 16'd1` and paths the command directly through the AXI Master Mover pipeline.

This causes single operations to execute on the external bus as highly efficient, **1-beat AXI bursts** (`xLEN = 8'h00`), keeping bus signals identical across all execution modes.

## **4\. Software Architecture (Python Environment)**

The host PC controls the hardware using a self-contained, console-optimized interface script (`ddr_test_cli_v1.py`). This script strips away heavy GUI engines to allow seamless execution inside standard Linux shell terminals or automated remote scripting setups.

### **User Interface Parameter Options**

* **`-p / --port` \[Required\]:** The physical Linux serial node connection entry path (e.g., `/dev/ttyUSB0`).  
* **`-b / --baud`:** Data serialization line speed. Defaults to **115200 Baud**.  
* **`--write` / `--read` \[Mutually Exclusive\]:** Decides the primary transaction loop path.  
* **`-a / --address`:** Target memory pointer in clean hex notation (e.g., `-a 0x0200`). The script features an automated sanitation hook that evaluates the pointer and automatically snaps it down to the nearest **64-bit boundary alignment** if it violates word cell bounds.  
* **`-s / --size`:** Data block footprint footprint constraint in total bytes. Options are locked to standard power-of-two footprints: `[8, 64, 128, 256, 512, 1024, 2048]`. A size of 8 automatically fires the single-mode opcodes.  
* **`-d / --data`:** A specific 64-bit hex value payload used for Single Writes, or used as a static seed value during fixed burst generation patterns.  
* **`--pattern`:** Chooses the data assembly profile for burst mode fills.

### **Data Generation Pattern Engine**

When running bulk write commands, the script handles data preparation using four built-in patterns:

```
  [counter]     --> 0x0000000000000000  0x0000000000000001  0x0000000000000002...
  [alternating] --> 0x5555555555555555  0xAAAAAAAAAAAAAAAA  0x5555555555555555...
  [fixed]       --> [User Hex Seed]     [User Hex Seed]     [User Hex Seed]...
  [random]      --> 0x9F4C1A23B8D86E01  0x23A10F43CD7782A9  0xB400E19A62F3104D...
```

## **5\. Silicon Resource Allocation & Budget Constraints**

When implementing memory arrays on compact silicon targets like the Microchip SmartFusion2 **M2S025** die, resource allocation is constrained by physical block RAM availability. The M2S025 contains exactly **31 Large SRAM (RAM1K18)** block primitives.

### **The Memory Budget Calculation Block**

To build a true dual-port, 64-bit wide staging buffer that can hold up to 2048 bytes of data, Libero must cluster multiple hardware blocks together:

Width Scaling Factor=18 bits primitive width64 bits bus width​→4 RAM1K18 blocks wide

A target memory address space (`ADDR_WIDTH`) parameter set to `16` builds a **64 KB** memory array. Stacking 4-block-wide structures 8 rows deep to hit 64 KB consumes **32 blocks**, immediately causing a fatal device overflow crash:

32 (AXI RAM blocks)+4 (Staging RAM blocks)=36 Total blocks required \>31 Physical block limit

### **Optimized Resolution Configuration**

To resolve this resource conflict, the `axi_ram` module address space parameter is downscaled to **`ADDR_WIDTH = 14`**, capping total memory capacity at **16 KB**. This shrinks the target memory footprint down to 2 rows of 4 blocks, cutting total device resource allocation down to a safe, sustainable level:

8 (Optimized AXI RAM blocks)+4 (Staging RAM blocks)=12 Active blocks utilized ≤31 Device limit

This optimization maintains full compatibility with your max burst size selection options (**2048 bytes**) while keeping block RAM consumption at a safe **38% total utilization rate**.

## **6\. Subsystem Execution Transcript**

Here is a typical transcript showing how the CLI utility executes a 512-byte block transfer write and read verification back-to-back over a point-to-point connection:

Bash

```
jijeesh@jijeesh-Latitude-5300:~$ python3 ddr_test_cli_v1.py --port /dev/ttyUSB0 --write -a 0x0200 -s 512 --pattern fixed -d 111111
```

Plaintext

```
[17:34:19.044] [SYS] Established physical wire connection context on interface: '/dev/ttyUSB0' at 115200 8N1.
[17:34:19.044] [SYS] ============ STARTING BURST WRITE (512 Bytes) TRANSACTION PIPELINE ============
[17:34:19.044] [SYS] STEP 1: Transmitting transaction opcode byte identifier directly down to FPGA layer...
[17:34:19.044] [TX]  TX -> [Opcode] : 0x33 (ASCII Character Frame: '3')
[17:34:19.044] [SYS] STEP 2: Awaiting opcode acknowledge token return flag ('a') from processing FSM...
[17:34:19.059] [RX]  RX <- [Token]  : 0x61 (ASCII Character Frame: 'a')
[17:34:19.060] [SYS] Handshake Phase 1 Verified successfully.
[17:34:19.060] [SYS] STEP 3: Broadcasting 32-bit register address destination array targeting bounds...
[17:34:19.060] [TX]  TX -> [Address] : 0x00000200 (Big-Endian byte footprint: [ 00 00 02 00 ])
[17:34:19.060] [SYS] STEP 4: Awaiting memory address latch loop acknowledge token return flag ('d') from core...
[17:34:19.075] [RX]  RX <- [Token]  : 0x64 (ASCII Character Frame: 'd')
[17:34:19.075] [SYS] Handshake Phase 2 Verified successfully.
[17:34:19.075] [SYS] STEP 5: Burst execution mode confirmed. Transmitting 16-bit stream word count limit constraint...
[17:34:19.076] [TX]  TX -> [Length]  : 64 Words (Hex: 0x0040 -> Big-Endian footprint: [ 00 40 ])
[17:34:19.076] [SYS] STEP 6: Awaiting dynamic loop tracker array allocation constraint acknowledge token ('l') from core...
[17:34:19.091] [RX]  RX <- [Token]  : 0x6C (ASCII Character Frame: 'l')
[17:34:19.091] [SYS] Handshake Phase 3 (Dynamic Burst Constraints) Verified successfully.
[17:34:19.092] [SYS] STEP 7: Transitioning system lines directly into Core Processing Payload Phase...
[17:34:19.092] [SYS] Assembling outbound binary stream package tracking strategy via strategy parameter pattern: 'fixed'
[17:34:19.092] [TX]  TX -> [Data Stream]: Dispatching 512 bytes binary package array to core line buffers...
[17:34:19.092] [SYS] Core transaction execution updates processed: Write operation completed successfully.
[17:34:19.092] [SYS] ============ TRANSACTION COMPLETED CLEANLY WITH ZERO ARTIFACTS ============
```

Bash

```
jijeesh@jijeesh-Latitude-5300:~$ python3 ddr_test_cli_v1.py --port /dev/ttyUSB0 --read -a 0x0200 -s 512 
```

Plaintext

```
[17:34:28.018] [SYS] Established physical wire connection context on interface: '/dev/ttyUSB0' at 115200 8N1.
[17:34:28.018] [SYS] ============ STARTING BURST READ (512 Bytes) TRANSACTION PIPELINE ============
[17:34:28.018] [SYS] STEP 1: Transmitting transaction opcode byte identifier directly down to FPGA layer...
[17:34:28.018] [TX]  TX -> [Opcode] : 0x34 (ASCII Character Frame: '4')
[17:34:28.018] [SYS] STEP 2: Awaiting opcode acknowledge token return flag ('a') from processing FSM...
[17:34:28.033] [RX]  RX <- [Token]  : 0x61 (ASCII Character Frame: 'a')
[17:34:28.033] [SYS] Handshake Phase 1 Verified successfully.
[17:34:28.033] [SYS] STEP 3: Broadcasting 32-bit register address destination array targeting bounds...
[17:34:28.033] [TX]  TX -> [Address] : 0x00000200 (Big-Endian byte footprint: [ 00 00 02 00 ])
[17:34:28.049] [SYS] STEP 4: Awaiting memory address latch loop acknowledge token return flag ('d') from core...
[17:34:28.049] [RX]  RX <- [Token]  : 0x64 (ASCII Character Frame: 'd')
[17:34:28.049] [SYS] Handshake Phase 2 Verified successfully.
[17:34:28.049] [SYS] STEP 5: Burst execution mode confirmed. Transmitting 16-bit stream word count limit constraint...
[17:34:28.049] [TX]  TX -> [Length]  : 64 Words (Hex: 0x0040 -> Big-Endian footprint: [ 00 40 ])
[17:34:28.049] [SYS] STEP 6: Awaiting dynamic loop tracker array allocation constraint acknowledge token ('l') from core...
[17:34:28.065] [RX]  RX <- [Token]  : 0x6C (ASCII Character Frame: 'l')
[17:34:28.065] [SYS] Handshake Phase 3 (Dynamic Burst Constraints) Verified successfully.
[17:34:28.065] [SYS] STEP 7: Transitioning system lines directly into Core Processing Payload Phase...
[17:34:28.065] [SYS] STEP 8: Dynamic read stream active. Awaiting internal storage compiling verification flag ('c') from core...
[17:34:28.065] [RX]  RX <- [Token]  : 0x63 (ASCII Character Frame: 'c')
[17:34:28.065] [SYS] STEP 9: Verification flag clear. Stripping down exactly 512 sequential payload bytes off the line...
[17:34:28.097] [RX]  RX <- [Bulk Stream]: Bulk collection pass parsed successfully. Captured 512 total stream bytes.

=====================================================================================
   CURRENT READ ELEMENT DATA MATRIX GRID TRANSCRIPT
=====================================================================================
  0x00000200 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000220 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000240 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000260 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000280 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000002A0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000002C0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000002E0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000300 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000320 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000340 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000360 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x00000380 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000003A0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000003C0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
  0x000003E0 | 0000000000111111  0000000000111111  0000000000111111  0000000000111111  
=====================================================================================
```

Would you like to expand this documentation to include the custom pin constraint files (`.pdc`) for physical placement on your SmartFusion2 development board?

