/*
 * Copyright 2020 Claude Schwarz
 * Copyright 2020 Niklas Ekström - rewrite in Verilog
 */
module pistorm(
    output reg      PI_TXN_IN_PROGRESS, // GPIO0
    output reg      PI_STATUS_CHANGED,  // GPIO1
    input   [1:0]   PI_SA,              // GPIO[3..2]
    input           PI_CLK,             // GPIO4
    input           PI_UNUSED,          // GPIO5
    input           PI_RD,              // GPIO6
    input           PI_WR,              // GPIO7
    inout   [15:0]  PI_SD,              // GPIO[23..8]

    output reg      LTCH_A_0,
    output reg      LTCH_A_8,
    output reg      LTCH_A_16,
    output reg      LTCH_A_24,
    output reg      LTCH_A_OE_n,
    output reg      LTCH_D_RD_U,
    output reg      LTCH_D_RD_L,
    output reg      LTCH_D_RD_OE_n,
    output reg      LTCH_D_WR_U,
    output reg      LTCH_D_WR_L,
    output reg      LTCH_D_WR_OE_n,

    input           M68K_CLK,
    output reg [2:0] M68K_FC,

    output reg      M68K_AS_n,
    output reg      M68K_UDS_n,
    output reg      M68K_LDS_n,
    output reg      M68K_RW,

    input           M68K_DTACK_n,
    input           M68K_BERR_n,

    input           M68K_VPA_n,
    output reg      M68K_E,
    output reg      M68K_VMA_n,

    input   [2:0]   M68K_IPL_n,

    inout           M68K_RESET_n,
    inout           M68K_HALT_n,

    input           M68K_BR_n,
    output reg      M68K_BG_n,
    input           M68K_BGACK_n
  );

  wire c125m = PI_CLK;

  localparam REG_DATA = 2'd0;
  localparam REG_ADDR_LO = 2'd1;
  localparam REG_ADDR_HI = 2'd2;
  localparam REG_STATUS = 2'd3;

  initial begin
    PI_TXN_IN_PROGRESS <= 1'b0;
    PI_STATUS_CHANGED <= 1'b0;

    LTCH_A_OE_n <= 1'b1;
    LTCH_D_WR_OE_n <= 1'b1;

    LTCH_D_RD_U <= 1'b0;
    LTCH_D_RD_L <= 1'b0;

    M68K_AS_n <= 1'b1;
    M68K_UDS_n <= 1'b1;
    M68K_LDS_n <= 1'b1;
    M68K_RW <= 1'b1;

    M68K_E <= 1'b0;
    M68K_VMA_n <= 1'b1;

    // TODO: Add handling of FC, include for every transaction.
    M68K_FC <= 3'd2;
    M68K_BG_n <= 1'b1;
  end

  always @(*) begin
    LTCH_D_WR_U <= PI_SA == REG_DATA && PI_WR;
    LTCH_D_WR_L <= PI_SA == REG_DATA && PI_WR;
    LTCH_A_0 <= PI_SA == REG_ADDR_LO && PI_WR;
    LTCH_A_8 <= PI_SA == REG_ADDR_LO && PI_WR;
    LTCH_A_16 <= PI_SA == REG_ADDR_HI && PI_WR;
    LTCH_A_24 <= PI_SA == REG_ADDR_HI && PI_WR;

    LTCH_D_RD_OE_n <= !(PI_SA == REG_DATA && PI_RD);
  end

  reg [2:0] ipl_0;
  reg [2:0] ipl_1;
  reg [2:0] ipl;
  reg [2:0] ipl_prev;

  always @(posedge c125m) begin
    if (c7m_falling) begin
      ipl_0 <= ~M68K_IPL_n;
      ipl_1 <= ipl_0;
    end

    if (ipl_0 == ipl_1)
      ipl <= ipl_1;

    ipl_prev <= ipl;
  end

  wire ipl_changed = ipl != ipl_prev;

  reg [2:0] rd_sync;
  reg [2:0] wr_sync;
  reg [15:0] sd_sync_0;
  reg [15:0] sd_sync_1;
  reg [1:0] sa_sync_0;
  reg [1:0] sa_sync_1;

  always @(posedge c125m) begin
    rd_sync <= {rd_sync[1:0], PI_RD};
    wr_sync <= {wr_sync[1:0], PI_WR};
    sd_sync_0 <= PI_SD;
    sd_sync_1 <= sd_sync_0;
    sa_sync_0 <= PI_SA;
    sa_sync_1 <= sa_sync_0;
  end

  wire rd_rising = !rd_sync[2] && rd_sync[1];
  wire wr_rising = !wr_sync[2] && wr_sync[1];

  reg [2:0] reset_in_n_sync;
  reg [2:0] halt_in_n_sync;
  reg [2:0] br_n_sync;
  reg [2:0] bgack_n_sync;

  always @(posedge c125m) begin
    reset_in_n_sync <= {reset_in_n_sync[1:0], M68K_RESET_n};
    halt_in_n_sync <= {halt_in_n_sync[1:0], M68K_HALT_n};
    br_n_sync <= {br_n_sync[1:0], M68K_BR_n};
    bgack_n_sync <= {bgack_n_sync[1:0], M68K_BGACK_n};
  end

  wire reset_in_n_changed = reset_in_n_sync[2] != reset_in_n_sync[1];
  wire halt_in_n_changed = halt_in_n_sync[2] != halt_in_n_sync[1];
  wire br_n_changed = br_n_sync[2] != br_n_sync[1];
  wire bgack_n_changed = bgack_n_sync[2] != bgack_n_sync[1];

  reg [15:0] data_out;
  wire data_out_oe = PI_SA == REG_STATUS && PI_RD;
  assign PI_SD = data_out_oe ? data_out : 16'bz;

  reg [15:0] status;

  reg reset_out_n = 1'b0;
  assign M68K_RESET_n = !reset_out_n ? 1'b0 : 1'bz;
  assign M68K_HALT_n = !reset_out_n ? 1'b0 : 1'bz;

  always @(posedge c125m) begin
    if (c7m_rising) begin
      reset_out_n <= status[1];
      M68K_BG_n <= !status[2];
    end
  end

  reg op_rw = 1'b1;
  reg op_uds_n = 1'b1;
  reg op_lds_n = 1'b1;
  reg op_res = 1'b0;

  reg a0;

  always @(posedge c125m) begin
    if (wr_rising) begin
      case (sa_sync_1)
        REG_ADDR_LO: begin
          a0 <= sd_sync_1[0];
        end

        REG_ADDR_HI: begin
          PI_TXN_IN_PROGRESS <= 1'b1;
          op_rw <= sd_sync_1[9];
          op_uds_n <= sd_sync_1[8] ? a0 : 1'b0;
          op_lds_n <= sd_sync_1[8] ? !a0 : 1'b0;
        end

        REG_STATUS: begin
          status <= sd_sync_1;
        end
      endcase
    end

    if (op_res)
      PI_TXN_IN_PROGRESS <= 1'b0;
  end

  // Interrupt handling.

  wire any_changed = ipl_changed || br_n_changed || bgack_n_changed || reset_in_n_changed || halt_in_n_changed;

  always @(posedge c125m) begin
    if (rd_rising && sa_sync_1 == REG_STATUS) begin
      data_out <= {ipl, 9'd0, br_n_sync[1], bgack_n_sync[1], reset_in_n_sync[1], halt_in_n_sync[1]};
      PI_STATUS_CHANGED <= 1'b0;
    end
    else if (any_changed) begin
      PI_STATUS_CHANGED <= 1'b1;
    end
  end

  // M68K state machine.

  reg [2:0] c7m_sync;
  reg [2:0] dtack_n_sync;
  reg [2:0] vpa_n_sync;

  always @(posedge c125m) begin
    c7m_sync <= {c7m_sync[1:0], M68K_CLK};
    dtack_n_sync <= {dtack_n_sync[1:0], M68K_DTACK_n};
    vpa_n_sync <= {vpa_n_sync[1:0], M68K_VPA_n};
  end

  wire c7m_rising = !c7m_sync[2] && c7m_sync[1];
  wire c7m_falling = c7m_sync[2] && !c7m_sync[1];

  reg [3:0] e_counter = 4'd0;

  always @(posedge c125m) begin
    if (c7m_falling) begin
      if (e_counter == 4'd9)
        e_counter <= 4'd0;
      else
        e_counter <= e_counter + 4'd1;
    end
  end

  always @(posedge c125m) begin
    if (c7m_falling) begin
      if (e_counter == 4'd9)
        M68K_E <= 1'b0;
      else if (e_counter == 4'd5)
        M68K_E <= 1'b1;
    end
  end

  reg [2:0] state = 3'd0;
  reg [2:0] latch_data_delay;

  always @(posedge c125m) begin
    op_res <= 1'b0;

    case (state)
      3'd0: begin
        if (c7m_falling) begin // S0 -> S1
          if (PI_TXN_IN_PROGRESS) begin
            LTCH_A_OE_n <= 1'b0;
            state <= state + 3'd1;
          end
        end
      end

      3'd1: begin
        if (c7m_rising) begin // S1 -> S2
          M68K_AS_n <= 1'b0;

          if (op_rw) begin
            M68K_UDS_n <= op_uds_n;
            M68K_LDS_n <= op_lds_n;
          end
          else begin
            M68K_RW <= 1'b0;
          end

          state <= state + 3'd1;
        end
      end

      3'd2: begin
        if (c7m_falling) begin // S2 -> S3
          if (!op_rw) begin
            LTCH_D_WR_OE_n <= 1'b0;
          end

          state <= state + 3'd1;
        end
      end

      3'd3: begin
        if (c7m_rising) begin // S3 -> S4
          if (!op_rw) begin
            M68K_UDS_n <= op_uds_n;
            M68K_LDS_n <= op_lds_n;
          end

          state <= state + 3'd1;
        end
      end

      3'd4: begin
        if (c7m_falling) begin // S4|Sw -> S5|Sw
          if (!dtack_n_sync[1]) begin
            state <= state + 3'd1;
          end
          else if (!vpa_n_sync[1] && e_counter == 4'd2) begin
            M68K_VMA_n <= 1'b0;
          end
          else if (!M68K_VMA_n && e_counter == 4'd8) begin
            state <= state + 3'd1;
          end
        end
      end

      3'd5: begin
        if (c7m_rising) begin // S5 -> S6
          // TODO: This delay must be calculated based on PI_CLK period.
          latch_data_delay <= 3'd3;
          state <= state + 3'd1;
        end
      end

      3'd6: begin
        if (latch_data_delay != 3'd0) begin
          latch_data_delay <= latch_data_delay - 3'd1;
        end

        if (latch_data_delay == 3'd1) begin
          LTCH_D_RD_U <= 1'b1;
          LTCH_D_RD_L <= 1'b1;
        end

        if (c7m_falling) begin // S6 -> S7
          M68K_VMA_n <= 1'b1;

          M68K_AS_n <= 1'b1;
          M68K_UDS_n <= 1'b1;
          M68K_LDS_n <= 1'b1;

          state <= state + 3'd1;
        end
      end

      3'd7: begin
        if (c7m_rising) begin // S7 -> S0
          op_res <= 1'b1;

          LTCH_D_RD_U <= 1'b0;
          LTCH_D_RD_L <= 1'b0;

          LTCH_A_OE_n <= 1'b1;
          LTCH_D_WR_OE_n <= 1'b1;

          M68K_RW <= 1'b1;

          state <= state + 3'd1;
        end
      end
    endcase
  end

endmodule
