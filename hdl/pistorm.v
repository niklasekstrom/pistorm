/*
 * Copyright 2020 Claude Schwarz
 * Copyright 2020 Niklas Ekström - rewrite in Verilog
 */
module pistorm(
    input           PI_CLK,   // GPIO4
    input   [2:0]   PI_SA,    // GPIO[5,3,2]
    inout   [15:0]  PI_SD,    // GPIO[23..8]
    input           PI_SOE_n, // GPIO6
    input           PI_SWE_n, // GPIO7
    output reg      PI_AUX0,  // GPIO0
    output reg      PI_AUX1,  // GPIO1

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

  initial begin
    PI_AUX0 <= 1'b0;
    PI_AUX1 <= 1'b0;

    LTCH_A_0 <= 1'b0;
    LTCH_A_8 <= 1'b0;
    LTCH_A_16 <= 1'b0;
    LTCH_A_24 <= 1'b0;
    LTCH_A_OE_n <= 1'b1;
    LTCH_D_RD_U <= 1'b0;
    LTCH_D_RD_L <= 1'b0;
    LTCH_D_RD_OE_n <= 1'b1;
    LTCH_D_WR_U <= 1'b0;
    LTCH_D_WR_L <= 1'b0;
    LTCH_D_WR_OE_n <= 1'b1;

    M68K_FC <= 3'd0;

    M68K_AS_n <= 1'b1;
    M68K_UDS_n <= 1'b1;
    M68K_LDS_n <= 1'b1;
    M68K_RW <= 1'b1;

    M68K_E <= 1'b0;
    M68K_VMA_n <= 1'b1;

    M68K_BG_n <= 1'b1;
  end

  reg [1:0] soe_n_sync;
  reg [1:0] swe_n_sync;

  always @(posedge c200m) begin
    soe_n_sync <= {soe_n_sync[0], PI_SOE_n};
    swe_n_sync <= {swe_n_sync[0], PI_SWE_n};
  end

  wire soe_n_falling = soe_n_sync[1] && !soe_n_sync[0];
  wire swe_n_falling = swe_n_sync[1] && !swe_n_sync[0];

  wire c200m = PI_CLK;

  reg [15:0] data_out;
  reg data_out_oe = 1'b0;
  assign PI_SD = data_out_oe ? data_out : 16'bz;

  reg [15:0] status;
  wire reset_n = status[1];

  assign M68K_RESET_n = !reset_n ? 1'b0 : 1'bz;
  assign M68K_HALT_n = !reset_n ? 1'b0 : 1'bz;

  reg op_req = 1'b0;
  reg op_rw = 1'b1;
  reg op_uds_n = 1'b1;
  reg op_lds_n = 1'b1;
  reg op_res = 1'b0;

  reg [1:0] pi_state = 2'd0;
  reg a0;

  always @(posedge c200m) begin

    op_req <= 1'b0;

    if (swe_n_falling) begin
      if (PI_SA[2]) begin
        if (PI_SA == 3'd4) begin
          status <= PI_SD;
        end
      end
      else begin // 68k access
        if (pi_state == 2'd0) begin
          a0 <= PI_SD[0];

          LTCH_A_0 <= 1'b1;
          LTCH_A_8 <= 1'b1;

          LTCH_A_16 <= 1'b0;
          LTCH_A_24 <= 1'b0;

          pi_state <= 2'd1;
        end
        else if (pi_state == 2'd1) begin
          LTCH_A_16 <= 1'b1;
          LTCH_A_24 <= 1'b1;

          LTCH_D_WR_U <= 1'b0;
          LTCH_D_WR_L <= 1'b0;

          pi_state <= 2'd2;
        end
        else if (pi_state == 2'd2) begin
          LTCH_D_WR_U <= 1'b1;
          LTCH_D_WR_L <= 1'b1;

          op_req <= 1'b1;
          op_rw <= 1'b0;
          op_uds_n <= PI_SA[1] ? a0 : 1'b0;
          op_lds_n <= PI_SA[1] ? !a0 : 1'b0;

          LTCH_A_0 <= 1'b0;
          LTCH_A_8 <= 1'b0;

          pi_state <= 2'd0;
        end
      end
    end

    if (soe_n_sync[0]) begin
      data_out_oe <= 1'b0;
      LTCH_D_RD_OE_n <= 1'b1;
    end
    else if (soe_n_falling) begin
      if (PI_SA[2]) begin
        if (PI_SA == 3'd4) begin
          data_out <= {~ipl_n, status[12:0]};
          data_out_oe <= 1'b1;
        end
      end
      else begin // 68k access
        op_req <= 1'b1;
        op_rw <= 1'b1;
        op_uds_n <= PI_SA[1] ? a0 : 1'b0;
        op_lds_n <= PI_SA[1] ? !a0 : 1'b0;

        LTCH_D_RD_OE_n <= 1'b0;

        LTCH_A_0 <= 1'b0;
        LTCH_A_8 <= 1'b0;

        pi_state <= 2'd0;
      end
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
    PI_AUX1 <= ipl_n == 3'b111;
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

  reg [1:0] aux0_state = 2'd0;

  always @(posedge c200m) begin
    case (aux0_state)
      2'd0: begin
        PI_AUX0 <= 1'b0;

        if (op_req) begin
          if (op_rw) begin
            aux0_state <= 2'd1;
          end
          else begin
            PI_AUX0 <= 1'b1;
            aux0_state <= 2'd2;
          end
        end
      end
      2'd1: begin
        if (op_res) begin
          PI_AUX0 <= 1'b1;
          aux0_state <= 2'd3;
        end
      end
      2'd2: begin
        if (op_res) begin
          PI_AUX0 <= 1'b0;
          aux0_state <= 2'd3;
        end
      end
      2'd3: begin
        if (soe_n_sync[0] && swe_n_sync[0]) begin
          aux0_state <= 2'd0;
        end
      end
    endcase
  end

endmodule
