#!/bin/bash
make clean
make -j8 build_dump.sc CFG=e_bp_unicore_ltb_cfg BR_PROFILE_P=1 PC_PROFILE_P=1 CORE_PROFILE_P=1 CMT_TRACE_P=1 VM_TRACE_P=1