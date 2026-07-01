/ Description:
//   This module acts as the primary top-level structural wrapper layer. It
//   implements a dedicated Staging Buffer Architecture designed to isolate 
//   slow asynchronous serial lines (UART) from a high-frequency system bus.
//
//   Operational Flow:
//     1. Write: Serial bytes are collected slowly into a 2KB Staging BRAM.
//        Once a burst finishes, the AXI Master Mover blasts the entire packet
//        onto the high-speed AXI fabric at 80 MHz in a single burst.
//     2. Read: High-speed AXI reads fetch data blocks from the target system
//        memory into the Staging Buffer RAM, which then streams data back 
//        to the host utility over UART.
//
// Dependencies:
//   - FCCC_C0               (SmartFusion2 Native Hard-IP Clock Block)
//   - uart_rx / uart_tx     (Physical Line Serialization Controllers)
//   - ram_2k_true_dual_port (Dual-Access Asymmetric Bridge RAM Layout)
//   - system_control_fsm    (5-bit Handshake Protocol Controller Engine)
//   - axi4_master_data_mover(High-Speed AXI4 Burst Controller Engine)
//   - axi_ram               (Alex Forencich System Memory Emulation target)
//
// Revision History:
//   v1.0 - Baseline 2KB hardcoded burst system loop.
//   v2.0 - Added dynamic 16-bit word length parameters handshake tracking.
//   v3.0 - Integrated 64-bit AXI4 Full Master pipeline & True Dual-Port BRAM.
//   v3.1 - Converted to 5-bit width FCCC-sync state tracking matrices.
//------------------------------------------------------------------------------
