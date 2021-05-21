
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_nonsynth_ltb_profiler
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
    `declare_bp_proc_params(bp_params_p)
    `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)

    , parameter ltb_trace_file_p = "ltb"
    )
   (input                         clk_i
    , input                       reset_i

    , input                        init_done_o

    // Synchronous read
    , input                              r_v_i
    , input [vaddr_width_p-1:0]          r_addr_i
    , input                              pred_v_o
    , input                              pred_conf_o
    , input                              pred_taken_o
    , input [ltb_cnt_width_p-1:0]        pred_non_spec_cnt_o
    , input [ltb_cnt_width_p-1:0]        pred_trip_cnt_o
    , input [ltb_cnt_width_p-1:0]        r_spec_cnt

    // Synchronous write
    , input                           w_v_i             // branch
    , input                           br_mispredict_i
    , input                           br_taken_i
    , input                           br_conf_i
    , input [vaddr_width_p-1:0]       br_src_addr_i
    , input [ltb_cnt_width_p-1:0]     br_non_spec_cnt_i
    , input [ltb_cnt_width_p-1:0]     br_trip_cnt_i
    , input [ltb_cnt_width_p-1:0]     w_spec_cnt
    , input                           w_yumi_o
    );

  logic r_v_r;
  bsg_dff_reset #(.width_p(1))
   r_reg
   (.clk_i(clk_i)
    ,.reset_i(reset_i)
    ,.data_i(r_v_i & r_addr_i == 'h80000130)
    ,.data_o(r_v_r)
   );

  // integer file_r;
  integer file;
  // string file_name_r;
  string file_name;
  wire reset_li = reset_i;
  always_ff @(negedge reset_li)
    begin
      file_name   = $sformatf("%s_w.stats", ltb_trace_file_p);
      file        = $fopen(file_name, "w");
      // file_name_r = $sformatf("%s_r.stats", ltb_trace_file_p);
      // file_r      = $fopen(file_name_r, "w");
    end

  always_ff @(negedge clk_i)
    if (reset_i) begin
    end
    else begin
      if (r_v_i) begin
        if (r_addr_i == 'h80000130) begin
          $fwrite(file, "r %x ",
            r_addr_i,
            );
        end
      end
      if (r_v_r) begin
        $fwrite(file, "%d %d %d %d %d 0\n",
          pred_taken_o,
          pred_conf_o,
          r_spec_cnt,
          pred_non_spec_cnt_o,
          pred_trip_cnt_o,
          );
      end
      if (w_v_i & w_yumi_o) begin
        if (br_src_addr_i == 'h80000130) begin
          $fwrite(file, "w %x %d %d %d %d %d %d\n",
            br_src_addr_i,
            br_taken_i,
            br_conf_i,
            w_spec_cnt,
            br_non_spec_cnt_i,
            br_trip_cnt_i,
            br_mispredict_i
            );
        end
      end
    end 

  longint key;
  int tmp;
  final
    begin
      $display("Hello from LTB profilerrrr\n");
      
      /*
      tmp = branch_histo.first(key);
      do begin
        $fwrite(file, "[%x] %d %d %d\n", key, branch_histo[key], miss_histo[key], (miss_histo[key]*100)/branch_histo[key]);
      end while (branch_histo.next(key));
      */

      /*
      foreach (branch_histo[key]) begin
        $fwrite(file, "[%x] %d %d %d\n", key, branch_histo[key], miss_histo[key], (miss_histo[key]*100)/branch_histo[key]);
      end
      */
    end

endmodule

