#!/bin/bash
prog=${1:-ltb_test}
make sim_dump.sc CFG=e_bp_unicore_ltb_cfg SUITE=bp-tests PROG=$prog
make sim_dump.sc SUITE=bp-tests PROG=$prog

ltb_folder=./results/verilator/bp_tethered.e_bp_unicore_ltb_cfg.none.sim.bp-tests.$prog
org_folder=./results/verilator/bp_tethered.e_bp_default_cfg.none.sim.bp-tests.$prog

python3 compare.py $ltb_folder/branch_0.csv $org_folder/branch_0.csv