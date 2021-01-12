/*
 * Copyright 2020 Claude Schwarz
 * Copyright 2020 Niklas Ekström - rewrite in Verilog
 */
module pistorm(
    output reg      PI_TXN_IN_PROGRESS, // GPIO0
    output reg      PI_IPL_ZERO,        // GPIO1
    input   [1:0]   PI_A,       // GPIO[3..2]
    input           PI_CLK,     // GPIO4
    input           PI_UNUSED,  // GPIO5
    input           PI_RD,      // GPIO6
    input           PI_WR,      // GPIO7
    inout   [15:0]  PI_D,       // GPIO[23..8]

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
    output  reg [2:0] M68K_FC,

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

  localparam REG_DATA = 2'd0;
  localparam REG_ADDR_LO = 2'd1;
  localparam REG_ADDR_HI = 2'd2;
  localparam REG_STATUS = 2'd3;

  initial begin
    PI_TXN_IN_PROGRESS <= 1'b0;
    PI_IPL_ZERO <= 1'b0;

    LTCH_A_OE_n <= 1'b1;
    LTCH_D_WR_OE_n <= 1'b1;
    LTCH_D_RD_U <= 1'b0;
    LTCH_D_RD_L <= 1'b0;

    M68K_FC <= 3'd0;

    M68K_AS_n <= 1'b1;
    M68K_UDS_n <= 1'b1;
    M68K_LDS_n <= 1'b1;
    M68K_RW <= 1'b1;

    M68K_E <= 1'b0;
    M68K_VMA_n <= 1'b1;

    M68K_BG_n <= 1'b1;
  end

  reg [1:0] rd_sync;
  reg [1:0] wr_sync;

  always @(posedge c200m) begin
    rd_sync <= {rd_sync[0], PI_RD};
    wr_sync <= {wr_sync[0], PI_WR};
  end

  wire rd_rising = !rd_sync[1] && rd_sync[0];
  wire wr_rising = !wr_sync[1] && wr_sync[0];

  wire c200m = PI_CLK;

  reg [15:0] data_out;
  assign PI_D = PI_A == REG_STATUS && PI_RD ? data_out : 16'bz;

  reg [15:0] status;
  wire reset_n = status[1];

  assign M68K_RESET_n = !reset_n ? 1'b0 : 1'bz;
  assign M68K_HALT_n = !reset_n ? 1'b0 : 1'bz;

  reg op_req = 1'b0;
  reg op_rw = 1'b1;
  reg op_uds_n = 1'b1;
  reg op_lds_n = 1'b1;
  reg op_res = 1'b0;

  always @(*) begin
    LTCH_D_WR_U <= PI_A == REG_DATA && PI_WR;
    LTCH_D_WR_L <= PI_A == REG_DATA && PI_WR;

    LTCH_A_0 <= PI_A == REG_ADDR_LO && PI_WR;
    LTCH_A_8 <= PI_A == REG_ADDR_LO && PI_WR;

    LTCH_A_16 <= PI_A == REG_ADDR_HI && PI_WR;
    LTCH_A_24 <= PI_A == REG_ADDR_HI && PI_WR;

    LTCH_D_RD_OE_n <= !(PI_A == REG_DATA && PI_RD);
  end

  reg a0;

  always @(posedge c200m) begin
    op_req <= 1'b0;

    if (op_res)
      PI_TXN_IN_PROGRESS <= 1'b0;

    if (wr_rising) begin
      case (PI_A)
        REG_ADDR_LO: begin
          a0 <= PI_D[0];
          PI_TXN_IN_PROGRESS <= 1'b1;
        end
        REG_ADDR_HI: begin
          op_req <= 1'b1;
          op_rw <= PI_D[9];
          op_uds_n <= PI_D[8] ? a0 : 1'b0;
          op_lds_n <= PI_D[8] ? !a0 : 1'b0;
        end
        REG_STATUS: begin
          status <= PI_D;
        end
      endcase
    end

    if (rd_rising && PI_A == REG_STATUS) begin
      data_out <= {~ipl_n, status[12:0]};
    end
  end

  reg [2:0] c7m_sync;
  reg [2:0] dtack_n_sync;
  reg [2:0] vpa_n_sync;

  always @(posedge c200m) begin
    c7m_sync <= {c7m_sync[1:0], M68K_CLK};
    dtack_n_sync <= {dtack_n_sync[1:0], M68K_DTACK_n};
    vpa_n_sync <= {vpa_n_sync[1:0], M68K_VPA_n};
  end

  wire c7m_rising = !c7m_sync[2] && c7m_sync[1];
  wire c7m_falling = c7m_sync[2] && !c7m_sync[1];

  reg [3:0] e_counter = 4'd0;

  always @(posedge c200m) begin
    if (c7m_falling) begin
      if (e_counter == 4'd9) begin
        M68K_E <= 1'b0;
        e_counter <= 4'd0;
      end
      else if (e_counter == 4'd5) begin
        M68K_E <= 1'b1;
        e_counter <= e_counter + 4'd1;
      end
      else begin
        e_counter <= e_counter + 4'd1;
      end
    end
  end

  reg [2:0] ipl_n = 3'b111;
  reg [2:0] ipl_n_1;
  reg [2:0] ipl_n_2;

  always @(posedge c200m) begin
    if (c7m_falling) begin
      ipl_n_1 <= M68K_IPL_n;
      ipl_n_2 <= ipl_n_1;
    end
    if (ipl_n_1 == ipl_n_2)
      ipl_n <= ipl_n_1;
    PI_IPL_ZERO <= ipl_n == 3'b111;
  end

  reg delayed_op_req;

  reg [2:0] state = 3'd0;
  reg [2:0] latch_data_delay;

  always @(posedge c200m) begin
    op_res <= 1'b0;

    if (op_req)
      delayed_op_req <= 1'b1;

    case (state)

      3'd0: begin
        if (c7m_falling) begin // S0 -> S1
          if (delayed_op_req) begin
            delayed_op_req <= 1'b0;
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
          latch_data_delay <= 3'd7;
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
        else if (c7m_falling) begin // S6 -> S7
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
