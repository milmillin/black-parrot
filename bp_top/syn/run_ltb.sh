#!/bin/bash
prog=${1:-ltb_test}
make sim_dump.sc CFG=e_bp_unicore_ltb_cfg SUITE=bp-tests PROG=$prog
#cat ./results/verilator/bp_tethered.e_bp_unicore_ltb_cfg.none.sim.bp-tests.$prog/branch_0.info