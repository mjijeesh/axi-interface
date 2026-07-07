#!/usr/bin/env python3
import tkinter as tk
from tkinter import ttk
from tkinter import messagebox
from tkinter import scrolledtext
import serial
import serial.tools.list_ports
import threading
import datetime
import random
import platform  # NEW: Imported to safely check operating system context

class RTG4DynamicHandshakeDebugger:
    def __init__(self, root):
        self.root = root
        self.root.title("RTG4 Dynamic Handshake Protocol Debugger")
        self.root.geometry("1040x760")
        self.root.resizable(False, False)
        
        self.ser = None
        
        # Application UI Variables
        self.port_var = tk.StringVar()
        self.transfer_type = tk.StringVar(value="Single")
        self.address_var = tk.StringVar(value="00000000")
        self.data_var = tk.StringVar(value="0123456789ABCDEF")
        self.pattern_var = tk.StringVar(value="Incremental Counter")
        self.burst_size_var = tk.StringVar(value="64") 
        self.status_var = tk.StringVar(value="Disconnected")
        
        self.build_ui_layout()
        self.refresh_com_ports()
        self.toggle_burst_size_widget()

    def build_ui_layout(self):
        # 1. Global Status Bar (Anchored at the absolute bottom)
        self.status_bar = tk.Label(self.root, textvariable=self.status_var, relief="sunken", anchor="w", font=("Arial", 9), bg="#E1E1E1", padx=8, pady=4)
        self.status_bar.pack(side="bottom", fill="x")

        master_container = ttk.Frame(self.root, padding=10)
        master_container.pack(fill="both", expand=True)

        # 2. Main Control Action Buttons Bar
        bottom_control = ttk.Frame(master_container, padding=5)
        bottom_control.pack(side="bottom", fill="x", pady=(5, 0))
        
        self.btn_connect = ttk.Button(bottom_control, text="Connect", command=self.handle_connect_toggle)
        self.btn_connect.pack(side="left", padx=5)
        self.btn_write = ttk.Button(bottom_control, text="Execute Write", state="disabled", command=lambda: self.dispatch_io_thread("Write"))
        self.btn_write.pack(side="left", padx=5)
        self.btn_read = ttk.Button(bottom_control, text="Execute Read", state="disabled", command=lambda: self.dispatch_io_thread("Read"))
        self.btn_read.pack(side="left", padx=5)
        ttk.Button(bottom_control, text="Exit", command=self.root.quit).pack(side="left", padx=5)

        # 3. Upper Component Row Frame
        upper_frame = ttk.Frame(master_container)
        upper_frame.pack(side="top", fill="x", expand=False, pady=(0, 10))

        # Left Panel (Input Form Blocks)
        left_panel = ttk.Frame(upper_frame, width=340)
        left_panel.pack(side="left", fill="both", expand=False, padx=(0, 10))
        left_panel.pack_propagate(True)
        
        # Block A: Serial Configs
        frame_serial = ttk.LabelFrame(left_panel, text="Serial Port Configuration", padding=6)
        frame_serial.pack(fill="x", pady=(0, 4))
        ttk.Label(frame_serial, text="COM Port").pack(side="left", padx=5)
        self.combo_ports = ttk.Combobox(frame_serial, textvariable=self.port_var, width=12, state="readonly")
        self.combo_ports.pack(side="left", padx=5)
        ttk.Button(frame_serial, text="⟳", width=3, command=self.refresh_com_ports).pack(side="left", padx=2)
        
        # Block B: Transmit settings with dynamic burst size choices dropdown
        frame_type = ttk.LabelFrame(left_panel, text="Data Transfer Configuration", padding=6)
        frame_type.pack(fill="x", pady=(0, 4))
        ttk.Radiobutton(frame_type, text="Single (8 - byte)", variable=self.transfer_type, value="Single", command=self.on_type_change).pack(anchor="w", pady=2)
        ttk.Radiobutton(frame_type, text="Burst Mode", variable=self.transfer_type, value="Burst", command=self.on_type_change).pack(anchor="w", pady=2)
        
        ttk.Label(frame_type, text="Select Burst Size (Bytes):").pack(anchor="w", pady=(4, 2))
        self.combo_burst_sizes = ttk.Combobox(frame_type, textvariable=self.burst_size_var, state="readonly", width=15)
        self.combo_burst_sizes['values'] = ("64", "128", "256", "512", "1024", "2048")
        self.combo_burst_sizes.pack(fill="x", pady=2)
        
        # Block C: Parameters Form
        frame_sdram = ttk.LabelFrame(left_panel, text="Memory Registry Fields", padding=6)
        frame_sdram.pack(fill="x", pady=(0, 4))
        addr_row = ttk.Frame(frame_sdram)
        addr_row.pack(fill="x", pady=2)
        ttk.Label(addr_row, text="Address (Hex)", width=12).pack(side="left")
        self.entry_addr = ttk.Entry(addr_row, textvariable=self.address_var, font=("Courier", 10))
        self.entry_addr.pack(side="left", fill="x", expand=True, padx=4)
        
        data_row = ttk.Frame(frame_sdram)
        data_row.pack(fill="x", pady=2)
        ttk.Label(data_row, text="Data (Hex)", width=12).pack(side="left")
        self.entry_data = ttk.Entry(data_row, textvariable=self.data_var, font=("Courier", 10))
        self.entry_data.pack(side="left", fill="x", expand=True, padx=4)

        # Block D: Pattern Engine
        frame_generator = ttk.LabelFrame(left_panel, text="Test Data Pattern Engine", padding=6)
        frame_generator.pack(fill="x", pady=(0, 4))
        self.combo_patterns = ttk.Combobox(frame_generator, textvariable=self.pattern_var, state="readonly")
        self.combo_patterns['values'] = ("Incremental Counter", "Alternating (55/AA)", "Fixed Constant", "Pseudorandom")
        self.combo_patterns.pack(fill="x", pady=2)
        ttk.Button(frame_generator, text="Generate Local Buffer", command=self.generate_test_pattern).pack(fill="x", pady=4)

        ttk.Label(left_panel, text="RTG4™", font=("Arial", 22, "bold italic"), foreground="#003366").pack(side="top", anchor="e", pady=5)

        # Right Panel Treeview Canvas Layout
        right_panel = ttk.LabelFrame(upper_frame, text="Internal FPGA RAM Matrix Layout", padding=8)
        right_panel.pack(side="right", fill="both", expand=True)
        scroll_y = ttk.Scrollbar(right_panel, orient="vertical")
        scroll_y.pack(side="right", fill="y")
        
        matrix_cols = ("Address", "Offset_00", "Offset_08", "Offset_10", "Offset_18")
        self.tree_read = ttk.Treeview(right_panel, columns=matrix_cols, show="headings", yscrollcommand=scroll_y.set, height=14)
        scroll_y.config(command=self.tree_read.yview)
        
        self.tree_read.heading("Address", text="Base Address")
        self.tree_read.heading("Offset_00", text="+00")
        self.tree_read.heading("Offset_08", text="+08")
        self.tree_read.heading("Offset_10", text="+10")
        self.tree_read.heading("Offset_18", text="+18")
        self.tree_read.column("Address", width=95, anchor="center", stretch=False)
        self.tree_read.column("Offset_00", width=125, anchor="center")
        self.tree_read.column("Offset_08", width=125, anchor="center")
        self.tree_read.column("Offset_10", width=125, anchor="center")
        self.tree_read.column("Offset_18", width=125, anchor="center")
        self.tree_read.pack(fill="both", expand=True)

        self.tree_read.bind("<Double-1>", self.on_cell_double_click)

        # Center Diagnostic Bus Monitor Pane
        terminal_frame = ttk.LabelFrame(master_container, text="Step-by-Step Hardware Handshake Diagnostic Monitor", padding=5)
        terminal_frame.pack(side="top", fill="both", expand=True, pady=(0, 5))
        self.txt_terminal = scrolledtext.ScrolledText(terminal_frame, font=("Courier", 9), bg="#1E1E1E", fg="#FFFFFF", wrap=tk.WORD)
        self.txt_terminal.pack(fill="both", expand=True)
        self.txt_terminal.config(state="disabled")
        self.txt_terminal.tag_config("TX", foreground="#64B5F6")   
        self.txt_terminal.tag_config("RX", foreground="#81C784")   
        self.txt_terminal.tag_config("SYS", foreground="#FFB74D")  
        self.txt_terminal.tag_config("ERR", foreground="#E57373")  

    def log(self, messages, tag="SYS"):
        timestamp = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]
        prefix = f"[{timestamp}] [{tag}] "
        def thread_safe_insert():
            self.txt_terminal.config(state="normal")
            self.txt_terminal.insert(tk.END, prefix, tag)
            self.txt_terminal.insert(tk.END, f"{messages}\n")
            self.txt_terminal.see(tk.END)
            self.txt_terminal.config(state="disabled")
        self.root.after(0, thread_safe_insert)

    def refresh_com_ports(self):
        """Discovers ports and filters out generic Linux motherboard serial lines."""
        all_ports = serial.tools.list_ports.comports()
        
        # NEW REFACTOR: Check if OS environment is Linux
        if platform.system() == "Linux":
            # Match only active USB hardware serial ports (ttyUSB and ttyACM)
            ports = [p.device for p in all_ports if "ttyUSB" in p.device or "ttyACM" in p.device]
        else:
            # Leave unfiltered if running on Windows (COM*) or macOS (cu.*)
            ports = [p.device for p in all_ports]
            
        self.combo_ports['values'] = ports
        if ports:
            self.combo_ports.current(0)
        else:
            self.combo_ports.set("") # Clear field display safely if zero links are detected

    def toggle_burst_size_widget(self):
        if self.transfer_type.get() == "Burst":
            self.combo_burst_sizes.config(state="readonly")
        else:
            self.combo_burst_sizes.config(state="disabled")

    def on_type_change(self):
        self.toggle_burst_size_widget()
        if self.transfer_type.get() == "Single":
            self.data_var.set("0123456789ABCDEF")
        else:
            self.data_var.set("FFFFAAAA89ABCDEF")

    def generate_test_pattern(self):
        pattern = self.pattern_var.get()
        is_burst = (self.transfer_type.get() == "Burst")
        burst_bytes = int(self.burst_size_var.get()) if is_burst else 8
        total_words = burst_bytes // 8 
        
        try:
            base_addr = self.validate_and_align_address(self.address_var.get(), is_burst)
        except Exception as e:
            messagebox.showerror("Error", str(e))
            return

        self.tree_read.delete(*self.tree_read.get_children())
        self.log(f"Assembling {burst_bytes}-Byte write cache via pattern: '{pattern}'", "SYS")
        
        words = []
        if pattern == "Incremental Counter":
            words = [idx & 0xFFFFFFFFFFFFFFFF for idx in range(total_words)]
        elif pattern == "Alternating (55/AA)":
            words = [0x5555555555555555 if idx % 2 == 0 else 0xAAAAAAAAAAAAAAAA for idx in range(total_words)]
        elif pattern == "Fixed Constant":
            try:
                const_val = int(self.data_var.get(), 16)
            except ValueError:
                messagebox.showerror("Error", "Provide valid Seed hex data inside Data field.")
                return
            words = [const_val & 0xFFFFFFFFFFFFFFFF] * total_words
        elif pattern == "Pseudorandom":
            words = [random.randint(0, 0xFFFFFFFFFFFFFFFF) for _ in range(total_words)]

        total_rows = (total_words + 3) // 4
        for row_idx in range(total_rows):
            offset = row_idx * 32
            row_addr = base_addr + offset
            row_vals = [f"{row_addr:08X}"]
            for c in range(4):
                w_idx = row_idx * 4 + c
                if w_idx < total_words:
                    row_vals.append(f"{words[w_idx]:016X}")
                else:
                    row_vals.append("---") 
            self.tree_read.insert("", "end", values=row_vals)
        self.log("Local UI matrix configuration populated.", "SYS")

    def handle_connect_toggle(self):
        if self.ser is None or not self.ser.is_open:
            port = self.port_var.get()
            if not port: 
                messagebox.showwarning("Warning", "No active Serial Interface Port selected.")
                return
            try:
                self.ser = serial.Serial(port, baudrate=115200, timeout=3.0)
                self.status_var.set(f"Connected : {port}")
                self.log(f"Opened link on {port} at 115200 8N1.", "SYS")
                self.btn_connect.config(text="Disconnect")
                self.btn_write.config(state="normal")
                self.btn_read.config(state="normal")
                self.combo_ports.config(state="disabled")
            except Exception as e:
                messagebox.showerror("Error", str(e))
        else:
            self.close_serial_connection()

    def close_serial_connection(self):
        if self.ser and self.ser.is_open: self.ser.close()
        self.ser = None
        self.status_var.set("Disconnected")
        self.btn_connect.config(text="Connect")
        self.btn_write.config(state="disabled")
        self.btn_read.config(state="disabled")
        self.combo_ports.config(state="readonly")

    def validate_and_align_address(self, current_addr, is_burst):
        addr_val = int(current_addr, 16)
        if addr_val % 8 != 0:
            addr_val = (addr_val // 8) * 8
            self.address_var.set(f"{addr_val:08X}")
        return addr_val

    def dispatch_io_thread(self, mode):
        threading.Thread(target=self.execute_protocol, args=(mode,), daemon=True).start()

    def execute_protocol(self, mode):
        if not self.ser or not self.ser.is_open: return
        self.btn_write.config(state="disabled")
        self.btn_read.config(state="disabled")
        
        is_burst = (self.transfer_type.get() == "Burst")
        burst_bytes = int(self.burst_size_var.get()) if is_burst else 8
        word_count = burst_bytes // 8 
        
        if mode == "Write":
            opcode = b'3' if is_burst else b'1'
        else:
            opcode = b'4' if is_burst else b'2'
            
        try:
            addr_int = self.validate_and_align_address(self.address_var.get(), is_burst)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            
            write_stream_buffer = bytearray()
            if mode == "Write" and is_burst:
                grid_items = self.tree_read.get_children()
                words_gathered = 0
                for item in grid_items:
                    row_vals = self.tree_read.item(item, "values")
                    for col_idx in range(1, 5):
                        if words_gathered < word_count:
                            word_int = int(row_vals[col_idx], 16)
                            write_stream_buffer.extend(word_int.to_bytes(8, byteorder='big'))
                            words_gathered += 1
                if words_gathered < word_count:
                    raise ValueError(f"Matrix grid lacks complete data pairs. Expected {word_count} words, found {words_gathered}.")

            if mode == "Read": 
                self.tree_read.delete(*self.tree_read.get_children())
                
            self.log(f"============ STARTING {mode.upper()} TRANSACTION (Size: {burst_bytes} Bytes) ============", "SYS")
            
            # --- STEP 1: OPCODE TRANSMISSION PHASE ---
            self.log(f"STEP 1: Transmitting Command Opcode character code to FPGA...", "SYS")
            self.ser.write(opcode)
            self.log(f"TX -> [Opcode] : 0x{opcode[0]:02X} (ASCII Character: '{opcode.decode()}')", "TX")
            
            # --- STEP 2: OPCODE HANDSHAKE VALIDATION PHASE ---
            self.log("STEP 2: Awaiting Opcode Acknowledgment Token ('a') from core...", "SYS")
            ack_a = self.ser.read(1)
            if not ack_a: 
                raise TimeoutError("Handshake Fault: Hardware failed to assert response byte within timeout window.")
            self.log(f"RX <- [Token]  : 0x{ack_a[0]:02X} (ASCII Character: '{ack_a.decode()}')", "RX")
            if ack_a != b'a': 
                raise ValueError(f"Handshake Mismatch: FSM out of sync. Expected 'a' (0x61), received: 0x{ack_a.hex().upper()}")
            self.log("Handshake Phase 1 Verified successfully.", "SYS")
                
            # --- STEP 3: ADDRESS TRANSMISSION PHASE ---
            self.log("STEP 3: Transmitting 32-bit destination register memory offset layout...", "SYS")
            addr_bytes = addr_int.to_bytes(4, byteorder='big')
            self.ser.write(addr_bytes)
            self.log(f"TX -> [Address] : 0x{addr_int:08X} (Byte stream: [ {addr_bytes.hex(' ').upper()} ])", "TX")
            
            # --- STEP 4: ADDRESS LOCK HANDSHAKE VALIDATION PHASE ---
            self.log("STEP 4: Awaiting Address Lock Acknowledgment Token ('d') from core...", "SYS")
            ack_d = self.ser.read(1)
            if not ack_d: 
                raise TimeoutError("Handshake Fault: Hardware dropped link before clamping address configuration parameter.")
            self.log(f"RX <- [Token]  : 0x{ack_d[0]:02X} (ASCII Character: '{ack_d.decode()}')", "RX")
            if ack_d != b'd': 
                raise ValueError(f"Handshake Mismatch: FSM out of sync. Expected 'd' (0x64), received: 0x{ack_d.hex().upper()}")
            self.log("Handshake Phase 2 Verified successfully.", "SYS")

            # --- STEP 5: DYNAMIC LENGTH TRANSMISSION PHASE (BURST MODES ONLY) ---
            if is_burst:
                self.log("STEP 5: Burst mode active. Broadcasting 16-bit payload word length constraint...", "SYS")
                len_bytes = word_count.to_bytes(2, byteorder='big')
                self.ser.write(len_bytes)
                self.log(f"TX -> [Length]  : {word_count} Words (0x{len_bytes.hex().upper()} -> [ {len_bytes.hex(' ').upper()} ])", "TX")
                
                # --- STEP 6: LENGTH ACKNOWLEDGMENT VALIDATION PHASE ---
                self.log("STEP 6: Awaiting Dynamic Length Acknowledgment Token ('l') from core...", "SYS")
                ack_l = self.ser.read(1)
                if not ack_l: 
                    raise TimeoutError("Handshake Fault: Hardware dropped link during active length parameter latch loop.")
                self.log(f"RX <- [Token]  : 0x{ack_l[0]:02X} (ASCII Character: '{ack_l.decode()}')", "RX")
                if ack_l != b'l': 
                    raise ValueError(f"Handshake Mismatch: FSM out of sync. Expected 'l' (0x6C), received: 0x{ack_l.hex().upper()}")
                self.log("Handshake Phase 3 (Dynamic Scaling Loop Constraints) Verified successfully.", "SYS")

            # --- STEP 7: CORE DATA BUS TRANSMISSION / READ DUMP COLLECTION PHASE ---
            self.log(f"STEP 7: Entering Processing Payload Core Data Phase...", "SYS")
            if mode == "Write":
                if not is_burst:
                    data_str = self.data_var.get().strip()
                    data_int = int(data_str, 16)
                    word_bytes = data_int.to_bytes(8, byteorder='big')
                    self.ser.write(word_bytes)
                    self.log(f"TX -> [Data Word]: 0x{data_int:016X} (Bytes: [ {word_bytes.hex(' ').upper()} ])", "TX")
                else:
                    self.log(f"TX -> [Data Stream]: Transmitting raw parallel byte blocks ({len(write_stream_buffer)} total payload bytes)...", "TX")
                    self.ser.write(write_stream_buffer)
                self.status_var.set("Write operation completed successfully")
                
            elif mode == "Read":
                if not is_burst:
                    self.log("Blocking for single 64-bit payload word return stream...", "SYS")
                    payload = self.ser.read(8)
                    if len(payload) < 8:
                        raise TimeoutError(f"Truncated Frame: Expected 8 payload bytes, only captured {len(payload)}.")
                    self.log(f"RX <- [Data Word]: 0x{payload.hex().upper()}", "RX")
                    self.tree_read.insert("", "end", values=(f"{addr_int:08X}", payload.hex().upper(), "---", "---", "---"))
                    self.data_var.set(payload.hex().upper())
                else:
                    # --- STEP 8: BUFFER COMPILED VALIDATION PHASE (BURST READ ONLY) ---
                    self.log("STEP 8: Burst Read active. Awaiting internal FPGA memory buffering confirmation flag ('c')...", "SYS")
                    ack_c = self.ser.read(1)
                    if not ack_c: 
                        raise TimeoutError("Handshake Fault: Inner memory controller failed verification pass step status checks.")
                    self.log(f"RX <- [Token]  : 0x{ack_c[0]:02X} (ASCII Character: '{ack_c.decode()}')", "RX")
                    if ack_c != b'c': 
                        raise ValueError(f"Handshake Mismatch: FSM out of sync. Expected 'c' (0x63), received: 0x{ack_c.hex().upper()}")
                    
                    # --- STEP 9: BULK STREAM COLLECTION PHASE ---
                    self.log(f"STEP 9: Verification passed. Capturing exactly {burst_bytes} continuous bytes directly from RAM FSM...", "SYS")
                    payload = self.ser.read(burst_bytes)
                    self.log(f"RX <- [Bulk Stream]: Download completed. Captured {len(payload)} bytes from data layer bus.", "RX")
                    if len(payload) < burst_bytes: 
                        raise TimeoutError(f"Truncated Array Buffer Chunks: Expected {burst_bytes} bytes, captured only {len(payload)}.")
                    
                    # Process and paint rows onto matrix grid view canvas
                    total_rows = (word_count + 3) // 4
                    for row_idx in range(total_rows):
                        base_offset = row_idx * 32
                        row_addr = addr_int + base_offset
                        row_vals = [f"{row_addr:08X}"]
                        
                        for word_idx in range(4):
                            w_num = row_idx * 4 + word_idx
                            if w_num < word_count:
                                chunk_offset = row_idx * 32 + (word_idx * 8)
                                word_bytes = payload[chunk_offset : chunk_offset + 8]
                                row_vals.append(f"{int.from_bytes(word_bytes, byteorder='big'):016X}")
                            else:
                                row_vals.append("---")
                        self.tree_read.insert("", "end", values=row_vals)
                self.status_var.set("Read operation completed successfully")

            self.log(f"============ TRANSACTION COMPLETED CLEANLY ============\n", "SYS")

        except Exception as err:
            self.log(f"PROTOCOL TRANSACTION EXCEPTION: {str(err)}", "ERR")
            self.log(f"================ TRANSACTION ABORTED SYSTEM TERMINATED ================\n", "ERR")
            self.status_var.set("Protocol Error / Operation Timed Out.")
            
        self.btn_write.config(state="normal")
        self.btn_read.config(state="normal")

    def on_cell_double_click(self, event):
        region = self.tree_read.identify_region(event.x, event.y)
        if region != "cell": return
        column = self.tree_read.identify_column(event.x)
        item = self.tree_read.identify_row(event.y)
        if column == "#1": return
        
        col_idx = int(column[1:]) - 1
        current_val = self.tree_read.item(item, "values")[col_idx]
        if current_val in ["---", ""]: return
        
        x, y, width, height = self.tree_read.bbox(item, column)
        self.entry_edit = ttk.Entry(self.tree_read, font=("Courier", 10), justify="center")
        self.entry_edit.place(x=x, y=y, width=width, height=height)
        self.entry_edit.insert(0, current_val)
        self.entry_edit.select_range(0, tk.END)
        self.entry_edit.focus_set()
        
        self.entry_edit.bind("<Return>", lambda e: self.save_cell_modification(item, col_idx))
        self.entry_edit.bind("<FocusOut>", lambda e: self.entry_edit.destroy())

    def save_cell_modification(self, item, col_idx):
        new_hex_val = self.entry_edit.get().strip().upper()
        self.entry_edit.destroy()
        if new_hex_val.startswith("0X"): new_hex_val = new_hex_val[2:]
        if not new_hex_val: return
        
        try:
            test_int = int(new_hex_val, 16)
            if test_int > 0xFFFFFFFFFFFFFFFF: raise ValueError()
            new_hex_val = f"{test_int:016X}"
        except ValueError:
            messagebox.showerror("Error", "Must be a valid hex value up to 64 bits.")
            return

        current_values = list(self.tree_read.item(item, "values"))
        current_values[col_idx] = new_hex_val
        self.tree_read.item(item, values=current_values)
        
        base_addr_int = int(current_values[0], 16)
        byte_offset = (col_idx - 1) * 8
        exact_target_cell_addr = base_addr_int + byte_offset
        
        self.address_var.set(f"{exact_target_cell_addr:08X}")
        self.data_var.set(new_hex_val)
        self.transfer_type.set("Single")
        self.toggle_burst_size_widget()
        self.log(f"Staged modified grid cell at address 0x{exact_target_cell_addr:08X} with data 0x{new_hex_val}.", "SYS")

if __name__ == "__main__":
    root = tk.Tk()
    app = RTG4DynamicHandshakeDebugger(root)
    root.protocol("WM_DELETE_WINDOW", lambda: [app.close_serial_connection(), root.destroy()])
    root.mainloop()
