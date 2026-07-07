#!/usr/bin/env python3
import argparse
import sys
import datetime
import random
import serial

# =========================================================================
# ANSI TERMINAL COLOR CONSTANTS FOR LINUX SHELLS
# =========================================================================
CLR_TX = "\033[94m"   # Light Blue for outbound transmissions
CLR_RX = "\033[92m"   # Light Green for inbound tokens/data
CLR_SYS = "\033[93m"  # Orange/Yellow for state execution milestones
CLR_ERR = "\033[91m"  # Red for fault scenarios and drop drops
CLR_RST = "\033[0m"   # Clear color coding back to baseline shell default

def log(message, tag="SYS"):
    """Prints a timestamped, color-coded diagnostic message to stdout."""
    timestamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
    color = CLR_SYS
    if tag == "TX": color = CLR_TX
    elif tag == "RX": color = CLR_RX
    elif tag == "ERR": color = CLR_ERR
    
    print(f"[{timestamp}] {color}[{tag}]{CLR_RST} {message}")

def validate_and_align_address(addr_str):
    """Parses hex string and ensures strict 64-bit boundary cell alignment."""
    try:
        addr_int = int(addr_str, 16)
    except ValueError:
        log(f"Invalid hexadecimal address format passed: '{addr_str}'", "ERR")
        sys.exit(1)
        
    if addr_int % 8 != 0:
        aligned = (addr_int // 8) * 8
        log(f"Target address 0x{addr_int:08X} unaligned to 64-bit word bounds. Automatically snapped to: 0x{aligned:08X}", "SYS")
        return aligned
    return addr_int

def generate_write_payload(pattern, size_bytes, raw_data_str):
    """Replicates the GUI pattern engine to compile data words for burst loops."""
    word_count = size_bytes // 8
    words = []
    
    if pattern == "counter":
        words = [idx & 0xFFFFFFFFFFFFFFFF for idx in range(word_count)]
    elif pattern == "alternating":
        words = [0x5555555555555555 if idx % 2 == 0 else 0xAAAAAAAAAAAAAAAA for idx in range(word_count)]
    elif pattern == "fixed":
        try:
            const_val = int(raw_data_str, 16)
        except ValueError:
            log(f"Data seed parameter must be clean hexadecimal format: '{raw_data_str}'", "ERR")
            sys.exit(1)
        words = [const_val & 0xFFFFFFFFFFFFFFFF] * word_count
    elif pattern == "random":
        words = [random.randint(0, 0xFFFFFFFFFFFFFFFF) for _ in range(word_count)]
        
    buffer = bytearray()
    for w in words:
        buffer.extend(w.to_bytes(8, byteorder='big'))
    return buffer

def print_matrix_layout(base_addr, payload_bytes):
    """Paints received streaming binary data into a clean text matrix table layout."""
    word_count = len(payload_bytes) // 8
    total_rows = (word_count + 3) // 4
    
    print("\n" + "="*85)
    print("   CURRENT READ ELEMENT DATA MATRIX GRID TRANSCRIPT")
    print("="*85)
    
    for row_idx in range(total_rows):
        row_offset = row_idx * 32
        row_addr = base_addr + row_offset
        row_str = f"  0x{row_addr:08X} | "
        
        for col_idx in range(4):
            w_num = row_idx * 4 + col_idx
            if w_num < word_count:
                chunk_start = row_idx * 32 + (col_idx * 8)
                word_slice = payload_bytes[chunk_start : chunk_start + 8]
                row_str += f"{word_slice.hex().upper()}  "
            else:
                row_str += "------------------  "
        print(row_str)
    print("="*85 + "\n")

# =========================================================================
# MAIN ARGUMENT EXECUTOR PANE
# =========================================================================
def main():
    # Constructing a visually structured user help guide using ANSI color flags
    HELP_EPILOG_MANUAL = f"""
=============================================================================
{CLR_SYS}QUICK START & USAGE EXAMPLES (LINUX UART CONTEXT){CLR_RST}
=============================================================================

1. Verifying Basic Connectivity (Single 8-Byte Word Read)
   {CLR_TX}python3 rtg4_dynamic_handshake_cli.py -p /dev/ttyUSB0 --read -a 00000010{CLR_RST}

2. Writing a Single Specific 64-bit Hex Word to an Address Index
   {CLR_TX}python3 rtg4_dynamic_handshake_cli.py -p /dev/ttyUSB0 --write -a 00000020 -d DEADBEEFCAFE1234{CLR_RST}

3. Executing a Dynamic Burst Write (e.g., 128 Bytes using an Oscillating Pattern)
   {CLR_TX}python3 rtg4_dynamic_handshake_cli.py -p /dev/ttyUSB0 --write -a 00000000 -s 128 --pattern alternating{CLR_RST}

4. Retrieving a Dynamic Burst Read Array (e.g., 256-Byte Core Memory Matrix Dump)
   {CLR_TX}python3 rtg4_dynamic_handshake_cli.py -p /dev/ttyUSB0 --read -a 00000000 -s 256{CLR_RST}

=============================================================================
{CLR_SYS}AUTOMATED OPERATIONAL MODE SELECTION MATRIX{CLR_RST}
=============================================================================
* Sizing Footprint Rules (-s / --size):
  -s 8          --> Hardware forces FSM into SINGLE mode (Opcodes '1' or '2')
  -s [64..2048] --> Hardware automatically scales into DYNAMIC BURST mode loops (Opcodes '3' or '4')

* Burst Dataset Insertion Patterns (--pattern):
  - counter     --> Generates sequential incremental tracking steps (0, 1, 2, 3...)
  - alternating --> Oscillates data blocks back-and-forth [0x5555555555555555 / 0xAAAAAAAAAAAAAAAA]
  - fixed       --> Broadcasts a unchanging user-defined hex value supplied via [-d / --data]
  - random      --> Injects pseudo-randomized 64-bit noise distributions into the target RAM blocks
"""

    parser = argparse.ArgumentParser(
        description="RTG4 Dynamic Handshake Protocol CLI Debugging & Verification Tool",
        epilog=HELP_EPILOG_MANUAL,
        formatter_class=argparse.RawDescriptionHelpFormatter # Preserves formatting layout spacing
    )
    
    # Connection Parameters
    parser.add_argument("-p", "--port", required=True, help="Target Linux serial interface connection path (e.g. /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="Line serialization speed constraint (default: 115200)")
    
    # Mutually Exclusive Action Flags
    action_group = parser.add_mutually_exclusive_group(required=True)
    action_group.add_argument("--write", action="store_true", help="Perform memory write transaction down to hardware storage space")
    action_group.add_argument("--read", action="store_true", help="Perform memory read array retrieval dump pass")
    
    # Payload Formatting Variables
    parser.add_argument("-a", "--address", default="00000000", help="Target base address pointer in hexadecimal notation (default: 00000000)")
    parser.add_argument("-s", "--size", type=int, default=8, choices=[8, 64, 128, 256, 512, 1024, 2048],
                        help="Transfer footprint allocation byte sizing parameters. 8 forces Single mode; higher flags dynamic loops. (default: 8)")
    parser.add_argument("-d", "--data", default="0123456789ABCDEF", help="64-bit Hex word value for Single writes OR pattern constant seed values")
    parser.add_argument("--pattern", choices=["counter", "alternating", "fixed", "random"], default="counter",
                        help="Structural dataset generation matrix strategy utilized for active burst transfers (default: counter)")

    # Redirect tool safely to display custom menu prints if syntax errors occur on entry points
    try:
        args = parser.parse_args()
    except SystemExit:
        print(HELP_EPILOG_MANUAL)
        sys.exit(0)

    # Step A: Validate and align input configurations
    addr_int = validate_and_align_address(args.address)
    is_burst = (args.size > 8)
    word_count = args.size // 8

    # Step B: Establish command instruction opcodes
    if args.write:
        opcode = b'3' if is_burst else b'1'
        mode_label = f"BURST WRITE ({args.size} Bytes)" if is_burst else "SINGLE WRITE (8 Bytes)"
    else:
        opcode = b'4' if is_burst else b'2'
        mode_label = f"BURST READ ({args.size} Bytes)" if is_burst else "SINGLE READ (8 Bytes)"

    # Step C: Instantiate core serial link wrapper
    try:
        ser = serial.Serial(args.port, baudrate=args.baud, timeout=3.0)
        log(f"Established physical wire connection context on interface: '{args.port}' at {args.baud} 8N1.", "SYS")
    except Exception as e:
        log(f"Critical failure opening requested serial wire instance: {e}", "ERR")
        print(HELP_EPILOG_MANUAL)
        sys.exit(1)

    try:
        # Purge interface lines prior to firing command frame transitions
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
        log(f"============ STARTING {mode_label} TRANSACTION PIPELINE ============", "SYS")
        
        # --- STEP 1: COMMAND OPCODE TRANSMISSION ---
        log("STEP 1: Transmitting transaction opcode byte identifier directly down to FPGA layer...", "SYS")
        ser.write(opcode)
        log(f"TX -> [Opcode] : 0x{opcode[0]:02X} (ASCII Character Frame: '{opcode.decode()}')", "TX")
        
        # --- STEP 2: OPCODE HANDSHAKE VALIDATION ---
        log("STEP 2: Awaiting opcode acknowledge token return flag ('a') from processing FSM...", "SYS")
        ack_a = ser.read(1)
        if not ack_a:
            raise TimeoutError("Handshake Fault: Hardware core dropped link state or failed to register transaction pulse.")
        log(f"RX <- [Token]  : 0x{ack_a[0]:02X} (ASCII Character Frame: '{ack_a.decode()}')", "RX")
        if ack_a != b'a':
            raise ValueError(f"Handshake Protocol Mismatch! Expected character 'a' (0x61), received: 0x{ack_a.hex().upper()}")
        log("Handshake Phase 1 Verified successfully.", "SYS")
        
        # --- STEP 3: BASE ADDRESS TRANSMISSION ---
        log("STEP 3: Broadcasting 32-bit register address destination array targeting bounds...", "SYS")
        addr_bytes = addr_int.to_bytes(4, byteorder='big')
        ser.write(addr_bytes)
        log(f"TX -> [Address] : 0x{addr_int:08X} (Big-Endian byte footprint: [ {addr_bytes.hex(' ').upper()} ])", "TX")
        
        # --- STEP 4: ADDRESS LOCK HANDSHAKE VALIDATION ---
        log("STEP 4: Awaiting memory address latch loop acknowledge token return flag ('d') from core...", "SYS")
        ack_d = ser.read(1)
        if not ack_d:
            raise TimeoutError("Handshake Fault: Hardware framework failed to confirm register bounds within window parameters.")
        log(f"RX <- [Token]  : 0x{ack_d[0]:02X} (ASCII Character Frame: '{ack_d.decode()}')", "RX")
        if ack_d != b'd':
            raise ValueError(f"Handshake Protocol Mismatch! Expected character 'd' (0x64), received: 0x{ack_d.hex().upper()}")
        log("Handshake Phase 2 Verified successfully.", "SYS")

        # --- STEP 5 & 6: DYNAMIC LENGTH TRANSMISSION (BURST OPERATIONS ONLY) ---
        if is_burst:
            log("STEP 5: Burst execution mode confirmed. Transmitting 16-bit stream word count limit constraint...", "SYS")
            len_bytes = word_count.to_bytes(2, byteorder='big')
            ser.write(len_bytes)
            log(f"TX -> [Length]  : {word_count} Words (Hex: 0x{len_bytes.hex().upper()} -> Big-Endian footprint: [ {len_bytes.hex(' ').upper()} ])", "TX")
            
            log("STEP 6: Awaiting dynamic loop tracker array allocation constraint acknowledge token ('l') from core...", "SYS")
            ack_l = ser.read(1)
            if not ack_l:
                raise TimeoutError("Handshake Fault: Logic processing layer dropped link tracking boundaries during frame setup loops.")
            log(f"RX <- [Token]  : 0x{ack_l[0]:02X} (ASCII Character Frame: '{ack_l.decode()}')", "RX")
            if ack_l != b'l':
                raise ValueError(f"Handshake Protocol Mismatch! Expected character 'l' (0x6C), received: 0x{ack_l.hex().upper()}")
            log("Handshake Phase 3 (Dynamic Burst Constraints) Verified successfully.", "SYS")

        # --- STEP 7: PAYLOAD DATA DISPATCH / INBOUND PAYLOAD COLLECTION STREAM ---
        log("STEP 7: Transitioning system lines directly into Core Processing Payload Phase...", "SYS")
        if args.write:
            if not is_burst:
                try:
                    single_word_int = int(args.data.strip(), 16)
                except ValueError:
                    raise ValueError(f"Single transmission word elements must be clear hex notation: '{args.data}'")
                word_bytes = single_word_int.to_bytes(8, byteorder='big')
                ser.write(word_bytes)
                log(f"TX -> [Data Word]: 0x{single_word_int:016X} (Bytes: [ {word_bytes.hex(' ').upper()} ])", "TX")
            else:
                log(f"Assembling outbound binary stream package tracking strategy via strategy parameter pattern: '{args.pattern}'", "SYS")
                stream_payload = generate_write_payload(args.pattern, args.size, args.data)
                log(f"TX -> [Data Stream]: Dispatching {len(stream_payload)} bytes binary package array to core line buffers...", "TX")
                ser.write(stream_payload)
            log("Core transaction execution updates processed: Write operation completed successfully.", "SYS")
            
        else: # Handle Read executions
            if not is_burst:
                log("Freezing process execution thread to await return of single 64-bit data word register...", "SYS")
                payload = ser.read(8)
                if len(payload) < 8:
                    raise TimeoutError(f"Truncated Frame Crash: Expected 8 parallel payload bytes, only fetched {len(payload)}.")
                log(f"RX <- [Data Word]: 0x{payload.hex().upper()}", "RX")
            else:
                # --- STEP 8: WAITING FOR STORAGE STABILITY STATUS ACK ---
                log("STEP 8: Dynamic read stream active. Awaiting internal storage compiling verification flag ('c') from core...", "SYS")
                ack_c = ser.read(1)
                if not ack_c:
                    raise TimeoutError("Handshake Fault: Internal memory array infrastructure failed sanity compilation loops.")
                log(f"RX <- [Token]  : 0x{ack_c[0]:02X} (ASCII Character Frame: '{ack_c.decode()}')", "RX")
                if ack_c != b'c':
                    raise ValueError(f"Handshake Protocol Mismatch! Expected character 'c' (0x63), received: 0x{ack_c.hex().upper()}")
                
                # --- STEP 9: READ BULK STREAM EXTRACTION ---
                log(f"STEP 9: Verification flag clear. Stripping down exactly {args.size} sequential payload bytes off the line...", "SYS")
                payload = ser.read(args.size)
                log(f"RX <- [Bulk Stream]: Bulk collection pass parsed successfully. Captured {len(payload)} total stream bytes.", "RX")
                if len(payload) < args.size:
                    raise TimeoutError(f"Incomplete payload block returned. Expected {args.size} bytes, line buffer dropped frames at count: {len(payload)}")
                
                # Render results to layout matrix grid console format
                print_matrix_layout(addr_int, payload)
                
            log("Core transaction execution updates processed: Read operation completed successfully.", "SYS")

        log("============ TRANSACTION COMPLETED CLEANLY WITH ZERO ARTIFACTS ============\n", "SYS")

    except Exception as err:
        log(f"CRITICAL HANDSHAKE DISCOVERY EXCEPTION: {err}", "ERR")
        log("==================== RUN TRANSACTION ARRESTED AND ABORTED ====================\n", "ERR")
        sys.exit(1)
    finally:
        ser.close()

if __name__ == "__main__":
    main()
