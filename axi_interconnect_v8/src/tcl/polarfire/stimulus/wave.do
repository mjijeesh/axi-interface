# ==============================================================================
# ModelSim / QuestaSim Waveform Configuration: wave.do
# Design: Async CoreFIFO (32b -> 64b) -> Autonomous AXI4 Master -> MSS Interrupt
# ==============================================================================

onerror {resume}
quietly WaveActivateNextPane {} 0

# Helper procedure: safely adds signals without aborting if an internal net name differs
proc add_wave_safe {args} {
    catch { eval add wave -noupdate $args }
}

# ------------------------------------------------------------------------------
# GROUP 1: Clocks & Resets
# ------------------------------------------------------------------------------
add_wave_safe -group {1. Clocks & Resets} -radix binary /tb_top_axi4/clk_50mhz
add_wave_safe -group {1. Clocks & Resets} -radix binary /tb_top_axi4/clk_100mhz
add_wave_safe -group {1. Clocks & Resets} -radix binary /tb_top_axi4/fifo_wclk
add_wave_safe -group {1. Clocks & Resets} -radix binary /tb_top_axi4/NSYSRESET
add_wave_safe -group {1. Clocks & Resets} -radix binary /tb_top_axi4/uut/reset_synchronizer_1_reset_sync

# ------------------------------------------------------------------------------
# GROUP 2: Data Generator (32-Bit Producer @ 75 MHz wclk)
# ------------------------------------------------------------------------------
add_wave_safe -group {2. Data Generator (32b)} -radix binary   /tb_top_axi4/gen_en
add_wave_safe -group {2. Data Generator (32b)} -radix binary   /tb_top_axi4/gen_reset
add_wave_safe -group {2. Data Generator (32b)} -radix binary   /tb_top_axi4/gen_random_delay
add_wave_safe -group {2. Data Generator (32b)} -radix hex      /tb_top_axi4/gen_pattern_tag
add_wave_safe -group {2. Data Generator (32b)} -radix unsigned /tb_top_axi4/gen_burst_len
add_wave_safe -group {2. Data Generator (32b)} -radix unsigned /tb_top_axi4/gen_delay_cycles
add_wave_safe -group {2. Data Generator (32b)} -radix unsigned /tb_top_axi4/gen_words_generated
add_wave_safe -group {2. Data Generator (32b)} -radix binary   /tb_top_axi4/uut/fifo_data_generator_0/in_delay
add_wave_safe -group {2. Data Generator (32b)} -radix unsigned /tb_top_axi4/uut/fifo_data_generator_0/delay_rem
add_wave_safe -group {2. Data Generator (32b)} -radix unsigned /tb_top_axi4/uut/fifo_data_generator_0/sample_idx

# ------------------------------------------------------------------------------
# GROUP 3: Async CoreFIFO (32-Bit Write -> 64-Bit Read CDC)
# ------------------------------------------------------------------------------
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/WCLOCK
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/WE
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix hex      /tb_top_axi4/uut/COREFIFO_C0_0/DATA
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/FULL
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/AFULL
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/RCLOCK
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/RE
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix hex      /tb_top_axi4/uut/COREFIFO_C0_0/Q
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix binary   /tb_top_axi4/uut/COREFIFO_C0_0/EMPTY
add_wave_safe -group {3. Async CoreFIFO (32b->64b)} -radix unsigned /tb_top_axi4/uut/COREFIFO_C0_0/RDCNT

# ------------------------------------------------------------------------------
# GROUP 4: AXI4 FIFO Master Control, Watermark & Idle-Flush FSM
# ------------------------------------------------------------------------------
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/stream_en
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/soft_rst
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix hex      /tb_top_axi4/base_address
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/buffer_size
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/burst_threshold
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/idle_flush_cycles
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/axi_busy
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/axi_err
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix hex      /tb_top_axi4/wr_offset
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/total_bytes_written
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/state
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/re_d1
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/skid_valid
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix hex      /tb_top_axi4/uut/axi4_fifo_master_0/skid_data
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/total_avail_words
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/idle_cnt
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/above_threshold
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/idle_flush_trigger
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/ready_to_burst
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/cand_beats
add_wave_safe -group {4. AXI4 Master Control & FSM} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/beats_rem

# ------------------------------------------------------------------------------
# GROUP 5: MSS PLIC Interrupt Handshake
# ------------------------------------------------------------------------------
add_wave_safe -group {5. MSS Interrupt Handshake} -radix binary   /tb_top_axi4/irq_en
add_wave_safe -group {5. MSS Interrupt Handshake} -radix binary   /tb_top_axi4/irq_ack
add_wave_safe -group {5. MSS Interrupt Handshake} -radix unsigned /tb_top_axi4/irq_chunk_bytes
add_wave_safe -group {5. MSS Interrupt Handshake} -radix binary   /tb_top_axi4/mss_irq
add_wave_safe -group {5. MSS Interrupt Handshake} -radix binary   /tb_top_axi4/mss_irq_pulse
add_wave_safe -group {5. MSS Interrupt Handshake} -radix unsigned /tb_top_axi4/irq_pending_cnt
add_wave_safe -group {5. MSS Interrupt Handshake} -radix hex      /tb_top_axi4/last_irq_offset
add_wave_safe -group {5. MSS Interrupt Handshake} -radix unsigned /tb_top_axi4/irq_ack_count
add_wave_safe -group {5. MSS Interrupt Handshake} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/irq_byte_accum
add_wave_safe -group {5. MSS Interrupt Handshake} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/irq_fire

# ------------------------------------------------------------------------------
# GROUP 6: AXI4 Master Write Channels (M0 -> CoreAXI4Interconnect)
# ------------------------------------------------------------------------------
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix hex      /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awid
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix hex      /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awaddr
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix unsigned /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awlen
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awsize
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awburst
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awvalid
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_awready
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix hex      /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_wdata
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix hex      /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_wstrb
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_wlast
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_wvalid
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_wready
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_bresp
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_bvalid
add_wave_safe -group {6. AXI4 Master M0 (Write)} -radix binary   /tb_top_axi4/uut/axi4_fifo_master_0/m_axi_bready

# ------------------------------------------------------------------------------
# GROUP 7: Slave 0 Target (64-Bit AXI4 SRAM @ 0x6000_0000)
# ------------------------------------------------------------------------------
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix hex      /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/AWADDR
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix unsigned /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/AWLEN
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/AWVALID
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/AWREADY
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix hex      /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/WDATA
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/WLAST
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/WVALID
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/WREADY
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/BRESP
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/BVALID
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C0_0/BREADY
add_wave_safe -group {7. Slave 0 SRAM (64b @ 0x6000_0000)} -radix unsigned /tb_top_axi4/s0_burst_cnt

# ------------------------------------------------------------------------------
# GROUP 8: Slave 1 Target (32-Bit DWC AXI4 SRAM @ 0x8000_0000)
# ------------------------------------------------------------------------------
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix hex      /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/AWADDR
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix unsigned /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/AWLEN
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/AWVALID
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/AWREADY
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix hex      /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/WDATA
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/WLAST
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/WVALID
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/WREADY
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/BRESP
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/BVALID
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix binary   /tb_top_axi4/uut/PF_SRAM_AHBL_AXI_C1_0/BREADY
add_wave_safe -group {8. Slave 1 SRAM (32b DWC @ 0x8000_0000)} -radix unsigned /tb_top_axi4/s1_burst_cnt

# ------------------------------------------------------------------------------
# GROUP 9: Testbench Scoreboard & Protocol Health
# ------------------------------------------------------------------------------
add_wave_safe -group {9. TB Scoreboard} -radix hex      /tb_top_axi4/active_base
add_wave_safe -group {9. TB Scoreboard} -radix unsigned /tb_top_axi4/proto_errors

# ------------------------------------------------------------------------------
# Waveform Window Formatting
# ------------------------------------------------------------------------------
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 280
configure wave -valuecolwidth 140
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {5000 ns}