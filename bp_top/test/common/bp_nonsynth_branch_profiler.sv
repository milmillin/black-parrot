
`include "bp_common_defines.svh"
`include "bp_top_defines.svh"

module bp_nonsynth_branch_profiler
  import bp_common_pkg::*;
  import bp_be_pkg::*;
  #(parameter bp_params_e bp_params_p = e_bp_default_cfg
    `declare_bp_proc_params(bp_params_p)
    `declare_bp_core_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)

    , parameter branch_trace_file_p = "branch"
    )
   (input                         clk_i
    , input                       reset_i
    , input                       freeze_i

    , input [`BSG_SAFE_CLOG2(num_core_p)-1:0] mhartid_i

    , input [fe_cmd_width_lp-1:0] fe_cmd_o
    , input                       fe_cmd_yumi_i

    , input                       commit_v_i
    );

  `declare_bp_core_if(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p);
  `declare_bp_fe_branch_metadata_fwd_s(btb_tag_width_p, btb_idx_width_p, bht_idx_width_p, ghist_width_p, vaddr_width_p, ltb_cnt_width_p);

  typedef enum
  {
    e_br, e_jal, e_jalr, e_call, e_ret, e_unknown
  } mk_branch_type_e;

  bp_fe_cmd_s fe_cmd;
  bp_fe_branch_metadata_fwd_s branch_metadata;
  assign fe_cmd = fe_cmd_o;

  wire pc_redirect_v    = fe_cmd_yumi_i & (fe_cmd.opcode == e_op_pc_redirection);
  wire attaboy_v        = fe_cmd_yumi_i & (fe_cmd.opcode == e_op_attaboy);

  wire br_miss_v = pc_redirect_v
    & (fe_cmd.operands.pc_redirect_operands.subopcode == e_subop_branch_mispredict);
  wire br_miss_taken = br_miss_v
    & (fe_cmd.operands.pc_redirect_operands.misprediction_reason == e_incorrect_pred_taken);
  wire br_miss_ntaken = br_miss_v
    & (fe_cmd.operands.pc_redirect_operands.misprediction_reason == e_incorrect_pred_ntaken);
  wire br_miss_nonbr = br_miss_v
    & (fe_cmd.operands.pc_redirect_operands.misprediction_reason == e_not_a_branch);
  
  assign attaboy_taken           = attaboy_v &  fe_cmd.operands.attaboy.taken;
  // assign attaboy_ntaken          = attaboy_v & ~fe_cmd_cast_i.operands.attaboy.taken;

  assign taken = attaboy_v ? attaboy_taken : br_miss_taken;

  assign branch_metadata = pc_redirect_v
                           ? fe_cmd.operands.pc_redirect_operands.branch_metadata_fwd
                           : fe_cmd.operands.attaboy.branch_metadata_fwd;

  mk_branch_type_e branch_type;
  always_comb begin
    if (branch_metadata.is_ret)
      branch_type = e_ret;
    else if (branch_metadata.is_call)
      branch_type = e_call;
    else if (branch_metadata.is_jalr)
      branch_type = e_jalr;
    else if (branch_metadata.is_jal)
      branch_type = e_jal;
    else if (branch_metadata.is_br)
      branch_type = e_br;
    else
      branch_type = e_unknown;
  end

  integer branch_histo [longint];
  integer miss_histo   [longint];

  integer instr_cnt;
  integer attaboy_cnt;
  integer redirect_cnt;
  integer br_cnt;
  integer jal_cnt;
  integer jalr_cnt;
  integer ret_cnt;
  integer btb_hit_cnt;
  integer ras_hit_cnt;
  integer bht_hit_cnt;

  integer file_3;
  string file_name_3;
  integer file_2;
  string file_name_2;
  integer file;
  string file_name;
  wire reset_li = reset_i | freeze_i;
  always_ff @(negedge reset_li)
    begin
      file_name = $sformatf("%s_%x.stats", branch_trace_file_p, mhartid_i);
      file      = $fopen(file_name, "w");
      file_name_2 = $sformatf("%s_%x.csv", branch_trace_file_p, mhartid_i);
      file_2      = $fopen(file_name_2, "w");
      file_name_3 = $sformatf("%s_%x.info", branch_trace_file_p, mhartid_i);
      file_3      = $fopen(file_name_3, "w");
      if (ltb_enabled_p)
        $fwrite(file_2, "le_instr,le_src,le_dst,le_mispred,le_taken,le_btb,le_ltb\n");
      else
        $fwrite(file_2, "instr,src,dst,mispred,taken,btb,ltb\n");
    end

  always_ff @(negedge clk_i)
    if (reset_i)
      begin
        instr_cnt    <= 0;
        attaboy_cnt  <= 0;
        redirect_cnt <= 0;
        br_cnt       <= 0;
        jal_cnt      <= 0;
        jalr_cnt     <= 0;
        ret_cnt      <= 0;
        btb_hit_cnt  <= 0;
        ras_hit_cnt  <= 0;
        bht_hit_cnt  <= 0;
      end
    else
      begin
        instr_cnt <= instr_cnt + commit_v_i;
        attaboy_cnt <= attaboy_cnt + attaboy_v;
        redirect_cnt <= redirect_cnt + pc_redirect_v;
        if ((attaboy_v | pc_redirect_v) & branch_metadata.is_br) begin
          $fwrite(file_2, "%d,[%x],[%x],%d,%d,%d,%d\n",
            instr_cnt,
            branch_metadata.src_vaddr,
            fe_cmd.vaddr,
            ~attaboy_v,
            taken,
            branch_metadata.src_btb,
            branch_metadata.src_ltb
          );
        end
        if (attaboy_v)
          begin
            br_cnt      <= br_cnt + branch_metadata.is_br;
            jal_cnt     <= jal_cnt + branch_metadata.is_jal;
            jalr_cnt    <= jalr_cnt + branch_metadata.is_jalr;
            ret_cnt     <= ret_cnt + branch_metadata.is_ret;

            btb_hit_cnt <= btb_hit_cnt + branch_metadata.src_btb;
            ras_hit_cnt <= ras_hit_cnt + branch_metadata.src_ret;
            bht_hit_cnt <= bht_hit_cnt + branch_metadata.is_br;

            if (branch_histo.exists(fe_cmd.vaddr))
              begin
                branch_histo[fe_cmd.vaddr] <= branch_histo[fe_cmd.vaddr] + 1;
                miss_histo[fe_cmd.vaddr] <= miss_histo[fe_cmd.vaddr] + 0;
              end
            else
              begin
                branch_histo[fe_cmd.vaddr] <= 1;
                miss_histo[fe_cmd.vaddr] <= 0;
              end
          end
        else if (pc_redirect_v)
          begin
            br_cnt   <= br_cnt + branch_metadata.is_br;
            jal_cnt  <= jal_cnt + branch_metadata.is_jal;
            jalr_cnt <= jalr_cnt + branch_metadata.is_jalr;
            ret_cnt     <= ret_cnt + branch_metadata.is_ret;

            if (branch_histo.exists(fe_cmd.vaddr))
              begin
                branch_histo[fe_cmd.vaddr] <= branch_histo[fe_cmd.vaddr] + 1;
                miss_histo[fe_cmd.vaddr]   <= miss_histo[fe_cmd.vaddr] + 1;
              end
            else
              begin
                branch_histo[fe_cmd.vaddr] <= 1;
                miss_histo[fe_cmd.vaddr]   <= 1;
              end
          end
      end

  longint key;
  int tmp;
  final
    begin
      $fwrite(file_3, "instr: %d\n", instr_cnt);
      $fwrite(file_3, "branch: %d\n", br_cnt);
      $fwrite(file_3, "jal: %d\n", jal_cnt);
      $fwrite(file_3, "jalr: %d\n", jalr_cnt);

      $fwrite(file, "Branch statistics\n");
      $fwrite(file, "# Instructions: %d\n", instr_cnt);
      $fwrite(file, "# Branch: %d\n", br_cnt);
      $fwrite(file, "# JAL: %d\n", jal_cnt);
      $fwrite(file, "# JALR: %d\n", jalr_cnt);
      $fwrite(file, "# ret: %d\n", ret_cnt);
      $fwrite(file, "# BTB Hit: %d\n", btb_hit_cnt);
      $fwrite(file, "# BHT Hit: %d\n", bht_hit_cnt);
      $fwrite(file, "# RAS Hit: %d\n", ras_hit_cnt);
      $fwrite(file, "# Attaboy: %d\n", attaboy_cnt);
      $fwrite(file, "# Redirect: %d\n", redirect_cnt);
      $fwrite(file, "MPKI: %d\n", (redirect_cnt * 1000) / instr_cnt);
      $fwrite(file, "BTB hit%%: %d\n", (btb_hit_cnt * 100) / (attaboy_cnt + redirect_cnt));
      $fwrite(file, "BHT hit%%: %d\n", (bht_hit_cnt * 100) / (br_cnt));
      $fwrite(file, "==================================== Branches ======================================\n");
      $fwrite(file, "[target\t]\t\toccurances\t\tmisses\t\tmiss%%]\n");

      $display("Hello from branch profilerrrr\n");
      
      tmp = branch_histo.first(key);
      do begin
        $fwrite(file, "[%x] %d %d %d\n", key, branch_histo[key], miss_histo[key], (miss_histo[key]*100)/branch_histo[key]);
      end while (branch_histo.next(key));

      /*
      foreach (branch_histo[key]) begin
        $fwrite(file, "[%x] %d %d %d\n", key, branch_histo[key], miss_histo[key], (miss_histo[key]*100)/branch_histo[key]);
      end
      */
    end

endmodule

