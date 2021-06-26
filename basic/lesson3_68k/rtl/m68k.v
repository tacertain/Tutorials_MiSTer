module sys
(
  input  wire        clk_25mhz,
  output wire [7:0]  led,
  output wire        ftdi_rxd,
  input  wire        ftdi_txd,

  //sdram
  output wire        sdram_clk,
  output wire        sdram_cke,
  output wire        sdram_csn,
  output wire        sdram_wen,
  output wire        sdram_rasn,
  output wire        sdram_casn,
  output wire  [1:0] sdram_ba,
  output wire [12:0] sdram_a,
  inout  wire [15:0] sdram_d,
  output wire  [1:0] sdram_dqm
);

  // reset for 1024 raw clocks
  reg [9:0] ctr = 0;
  always @(posedge clk_25mhz) if (!pwr_up_reset_n) ctr <= ctr+1;
  wire pwr_up_reset_n = (&ctr);

  // ===============================================================
  // 68000 CPU
  // ===============================================================
  
  // clock generation
  reg  fx68_phi1 = 0; 
  wire fx68_phi2 = !fx68_phi1;

  always @(posedge clk_25mhz) begin
    fx68_phi1 <= ~fx68_phi1;
  end

  wire clk100_mhz;
  
  PLL pll (
    .clkin(clk_25mhz),
    .pll100(clk100_mhz)
  );

  // CPU outputs
  wire cpu_rw;                   // Read = 1, Write = 0
  wire cpu_as_n;                 // Address strobe
  wire cpu_lds_n;                // Lower byte strobe
  wire cpu_uds_n;                // Upper byte strobe
  wire cpu_E;                    // Peripheral clock
  wire vma_n;                    // Valid peripheral memory address
  wire [2:0]cpu_fc;              // Processor state
  wire cpu_reset_n_o;            // Reset output signal
  wire cpu_halted_n;             // Halt output
  wire bg_n;                     // Bus grant

  // CPU busses
  wire [15:0] cpu_dout;          // Data from CPU
  wire [23:0] cpu_a;             // Address
  wire [15:0] cpu_din;           // Data to CPU

  // CPU inputs
  wire berr_n = 1'b1;            // Bus error (never error)
  wire dtack_n = !vpa_n;         // Data transfer ack (always ready)
  wire vpa_n;                    // Valid peripheral address detected
  reg  cpu_br_n = 1'b1;          // Bus request
  reg  bgack_n = 1'b1;           // Bus grant ack
  reg  ipl0_n = 1'b1;            // Interrupt request signals
  reg  ipl1_n = 1'b1;
  reg  ipl2_n = 1'b1;
  
  assign cpu_a[0] = 0;           // to make gtk wave easy

  fx68k fx68k (
    // input
    .clk( clk_25mhz),
    .enPhi1(fx68_phi1),
    .enPhi2(fx68_phi2),
    .extReset(!pwr_up_reset_n),
    .pwrUp(!pwr_up_reset_n),
    .HALTn(pwr_up_reset_n),
    
    // output
    .eRWn(cpu_rw),
    .ASn( cpu_as_n),
    .LDSn(cpu_lds_n),
    .UDSn(cpu_uds_n),
    .E(cpu_E),
    .VMAn(vma_n),
    .FC0(cpu_fc[0]),
    .FC1(cpu_fc[1]),
    .FC2(cpu_fc[2]),
    .BGn(bg_n),
    .oRESETn(cpu_reset_n_o),
    .oHALTEDn(cpu_halted_n),

    // input
    .VPAn(vpa_n),         
    .DTACKn(dtack_n), 
    .BERRn(berr_n), 
    .BRn(cpu_br_n),  
    .BGACKn(bgack_n),
    .IPL0n(ipl0_n),
    .IPL1n(ipl1_n),
    .IPL2n(ipl2_n),

    // busses
    .iEdb(cpu_din),
    .oEdb(cpu_dout),
    .eab(cpu_a[23:1])
  );

  wire rom_csn = !(cpu_a[23:18]==6'b000000) | cpu_as_n;
//  wire ram_csn = !(cpu_a[23:18]==6'b000100) | cpu_as_n;
  wire sdr_csn = !(cpu_a[23:18]==6'b000100) | cpu_as_n;
  assign vpa_n = !(cpu_a[23:18]==6'b011000) | cpu_as_n;
  wire acia_cs = !vma_n;
  
  wire [15:0] rom_do;
  wire [15:0] ram_do;
  wire [15:0] sdr_do;
  wire [ 7:0] acia_do;
  assign cpu_din = !rom_csn ? rom_do :
//                   !ram_csn ? ram_do :
                   !sdr_csn ? sdr_do :
                    acia_cs ? {8'd0, acia_do } :
                   16'd0;
/*
  RAM ram(
    .CLK(clk_25mhz),
    .nCS(ram_csn),
    .nWE(cpu_rw),
    .nLDS(cpu_lds_n),
    .nUDS(cpu_uds_n),
    .ADDR(cpu_a[17:1]),
    .DI(cpu_dout),
    .DO(ram_do)
  );
*/
  ROM rom(
    .CLK(clk_25mhz),
    .nCS(rom_csn),
    .ADDR(cpu_a[13:1]),
    .DO(rom_do)
  );

  reg baudclk; // 16 * 9600 = 153600 = 25Mhz/163
  reg [7:0] baudctr = 0;
  always @(posedge clk_25mhz) begin
    baudctr <= baudctr + 1;
    baudclk <= baudctr[7];
    if(baudctr == 162) baudctr <= 0;
  end

  // 9600 8N1
  ACIA acia(
    .clk(clk_25mhz),
    .reset(!pwr_up_reset_n),
    .cs(acia_cs),
    .e_clk(cpu_E),
    .rw_n(cpu_rw),
    .rs(cpu_a[1]),
    .data_in(cpu_dout[7:0]),
    .data_out(acia_do),
    .txclk(baudclk),
    .rxclk(baudclk),
    .cts_n(1'b0),
    .dcd_n(1'b0),
    .txdata(ftdi_rxd),
    .rxdata(ftdi_txd)
  );
  
  SDRAM sdram(
    .clk_in(clk100_mhz),

    // cpu side
    .din(cpu_dout),
    .dout(sdr_do),
    .addr({1'b0, cpu_a[23:1]}),
    .udsn(cpu_uds_n),
    .ldsn(cpu_lds_n),
    .asn(sdr_csn),
    .rw(cpu_rw),
    .rst(!pwr_up_reset_n),
    
    // sdram side
    .sd_data(sdram_d),
    .sd_addr(sdram_a),
    .sd_dqm(sdram_dqm),
    .sd_ba(sdram_ba),
    .sd_cs(sdram_csn),
    .sd_we(sdram_wen),
    .sd_ras(sdram_rasn),
    .sd_cas(sdram_casn),
    .sd_cke(sdram_cke),
    .sd_clk(sdram_clk)
  );

  assign led = cpu_a[7:0];
  
endmodule

