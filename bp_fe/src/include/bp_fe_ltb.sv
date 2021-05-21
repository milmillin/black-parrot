/*
 * bp_fe_ltb.v
 *
 * Loop Termination Buffer (LTB).
 * Partial implementation of https://cseweb.ucsd.edu/~calder/papers/ISHPC2K-LOOP.pdf
 */

`include "bp_common_defines.svh"
`include "bp_fe_defines.svh"

module bp_fe_ltb
 import bp_common_pkg::*;
 import bp_fe_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)
   )
  (input                              clk_i
   , input                            reset_i

   , output logic                     init_done_o

   // Synchronous read
   , input                              r_v_i
   , input [vaddr_width_p-1:0]          r_addr_i
   , input                              r_retry_i      // won't write
   , output logic                       pred_v_o
   , output logic                       pred_conf_o
   , output logic                       pred_taken_o
   , output logic [ltb_cnt_width_p-1:0] pred_non_spec_cnt_o
   , output logic [ltb_cnt_width_p-1:0] pred_trip_cnt_o

   // Synchronous write
   , input                            w_v_i             // branch
   , input                            br_mispredict_i
   , input                            br_taken_i
   , input                            br_conf_i
   , input [vaddr_width_p-1:0]        br_src_addr_i
   , input [ltb_cnt_width_p-1:0]      br_non_spec_cnt_i
   , input [ltb_cnt_width_p-1:0]      br_trip_cnt_i
   , output logic                     w_yumi_o
   );

  ///////////////////////
  // Initialization state machine
  enum logic [1:0] {e_reset, e_clear, e_run} state_n, state_r;
  wire is_reset = (state_r == e_reset);
  wire is_clear = (state_r == e_clear);
  wire is_run   = (state_r == e_run);

  assign init_done_o = is_run;

  localparam ltb_els_lp = 2**ltb_idx_width_p;
  localparam ltb_max_cnt_lp = 2**ltb_cnt_width_p;
  logic [`BSG_WIDTH(ltb_els_lp)-1:0] init_cnt;
  bsg_counter_clear_up
   #(.max_val_p(ltb_els_lp), .init_val_p(0))
   init_counter
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.clear_i(1'b0)
     ,.up_i(is_clear)
     ,.count_o(init_cnt)
     );
  wire finished_init = (init_cnt == ltb_els_lp-1'b1);

  always_comb
    case (state_r)
      e_clear: state_n = finished_init ? e_run : e_clear;
      e_run  : state_n = e_run;
      // e_reset
      default: state_n = e_clear;
    endcase

  //synopsys sync_set_reset "reset_i"
  always_ff @(posedge clk_i)
    if (reset_i)
      state_r <= e_reset;
    else
      state_r <= state_n;

  ////////////////////////
  // End Initialization Part

  typedef struct packed
  {
    logic [ltb_tag_width_p-1:0] tag;
    logic [ltb_cnt_width_p-1:0] non_spec_cnt;
    logic [ltb_cnt_width_p-1:0] trip_cnt;
    logic                       conf;
  }  bp_ltb_entry_s;

  wire [ltb_idx_width_p-1:0] r_idx_li = r_addr_i[2+:ltb_idx_width_p];
  wire [ltb_tag_width_p-1:0] r_tag_li = r_addr_i[2+ltb_idx_width_p+:ltb_tag_width_p];
  wire [ltb_idx_width_p-1:0] w_idx_li = br_src_addr_i[2+:ltb_idx_width_p];
  wire [ltb_tag_width_p-1:0] w_tag_li = br_src_addr_i[2+ltb_idx_width_p+:ltb_tag_width_p];

  wire rw_same_addr = r_v_i & ~r_retry_i & w_v_i & (r_idx_li == w_idx_li);

  logic [ltb_els_lp-1:0]      r_idx_one_hot;
  logic [ltb_els_lp-1:0]      w_idx_one_hot;

  bp_ltb_entry_s              tag_mem_data_lo;
  wire                        tag_mem_r_v_li    = r_v_i;
  wire [ltb_idx_width_p-1:0]  tag_mem_r_addr_li = r_idx_li;

  logic [ltb_cnt_width_p-1:0] spec_cnt_r[ltb_els_lp-1:0];

  bp_ltb_entry_s              tag_mem_data_li;
  wire                        tag_mem_w_v_li    = is_clear | (w_v_i & ~rw_same_addr);
  wire [btb_idx_width_p-1:0]  tag_mem_w_addr_li = is_clear ? init_cnt : w_idx_li;

  logic [ltb_cnt_width_p-1:0] non_spec_cnt_plus1;
  // logic [ltb_cnt_width_p-1:0] w_spec_cnt;
  // logic [ltb_cnt_width_p-1:0] r_spec_cnt;

  // assign w_spec_cnt          = spec_cnt_lo[w_idx_li];
  // assign r_spec_cnt          = spec_cnt_lo[r_idx_li];
  assign non_spec_cnt_plus1  = br_non_spec_cnt_i + 1;

  bsg_decode #(.num_out_p(ltb_els_lp))
   r_idx_decode
    (.i(r_idx_li)
     ,.o(r_idx_one_hot));

  bsg_decode #(.num_out_p(ltb_els_lp))
   w_idx_decode
    (.i(w_idx_li)
     ,.o(w_idx_one_hot));

  for (genvar i = 0; i < ltb_els_lp; i++)
    begin : spec_counters
      // logic reset_spec = pred_v_n & ~pred_taken_n & r_idx_one_hot[i];
      logic reset_mispredict = w_v_i & ~rw_same_addr & br_mispredict_i &
                                ~br_taken_i & w_idx_one_hot[i];
      
      logic [ltb_cnt_width_p-1:0] spec_cnt_n;
      always_comb begin
        if (reset_i | reset_mispredict)
          spec_cnt_n = '0;
        else if (w_v_i & ~rw_same_addr & ~br_taken_i & w_idx_one_hot[i])
          spec_cnt_n = spec_cnt_r[i] - non_spec_cnt_plus1;
        else if (r_v_i & ~r_retry_i & r_idx_one_hot[i] & r_tag_li == tag_mem_data_lo.tag) begin
          if (tag_mem_data_lo.conf & (spec_cnt_r[i] == tag_mem_data_lo.trip_cnt))
            spec_cnt_n = '0;
          else
            spec_cnt_n = spec_cnt_r[i] + 1;
        end else
          spec_cnt_n = spec_cnt_r[i];
      end

      bsg_dff #(.width_p(ltb_cnt_width_p))
        spec_counter
        (.clk_i(clk_i)
         ,.data_i(spec_cnt_n)
         ,.data_o(spec_cnt_r[i])
         );
    end

  // TAG MEM

  always_comb begin : w_data_li
    if (is_clear)
      tag_mem_data_li = '0;
    else begin
      if (br_taken_i)
        tag_mem_data_li = '{tag: w_tag_li, 
                            non_spec_cnt: non_spec_cnt_plus1,
                            trip_cnt: br_trip_cnt_i, 
                            conf: br_conf_i};
      else begin
        // not taken
        tag_mem_data_li = '{tag: w_tag_li,
                            non_spec_cnt: '0,
                            trip_cnt: br_non_spec_cnt_i,
                            conf: (br_trip_cnt_i != 0) & (br_non_spec_cnt_i == br_trip_cnt_i)};
      end
    end
  end

  // ASYNC MEM
  bsg_mem_1r1w
   #(.width_p($bits(bp_ltb_entry_s)), .els_p(ltb_els_lp))
   tag_mem
    (.w_clk_i(clk_i)
     ,.w_reset_i(reset_i)

     ,.w_v_i(tag_mem_w_v_li)
     ,.w_addr_i(tag_mem_w_addr_li)
     ,.w_data_i(tag_mem_data_li)

     ,.r_v_i(tag_mem_r_v_li)
     ,.r_addr_i(tag_mem_r_addr_li)
     ,.r_data_o(tag_mem_data_lo)
     );
  assign w_yumi_o = is_run & w_v_i & ~rw_same_addr;

  // r_v_i reg
  logic                       r_v_r;
  logic [ltb_tag_width_p-1:0] r_tag_r;
  logic [ltb_idx_width_p-1:0] r_idx_r;
  bsg_dff_reset
   #(.width_p(1+ltb_tag_width_p+ltb_idx_width_p))
   r_v_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.data_i({r_v_i, r_tag_li, r_idx_li})
     ,.data_o({r_v_r, r_tag_r, r_idx_r})
    );

  // output reg
  bp_ltb_entry_s tag_mem_data_r;
  bsg_dff_reset_en
   #(.width_p($bits(bp_ltb_entry_s)))
   pred_reg
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.en_i(r_v_i)
     ,.data_i(tag_mem_data_lo)
     ,.data_o(tag_mem_data_r)
     );
  
  assign pred_v_o            = r_v_r & (tag_mem_data_r.tag == r_tag_r);
  assign pred_conf_o         = tag_mem_data_r.conf;
  assign pred_taken_o        = ~(spec_cnt_r[r_idx_r] == 0);
  assign pred_non_spec_cnt_o = tag_mem_data_r.non_spec_cnt;
  assign pred_trip_cnt_o     = tag_mem_data_r.trip_cnt;

  // debug
  logic [ltb_cnt_width_p-1:0] r_spec_cnt = spec_cnt_r[r_idx_r];
endmodule

