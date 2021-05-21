#!/bin/bash
prog=${1:-ltb_test}
make sim_dump.sc SUITE=bp-tests PROG=$prog
