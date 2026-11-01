#!/bin/bash
# run_all.sh - Linux flow (VCS or Xcelium, pick one block) + coverage merge
# Usage: ./run_all.sh            (from sim/)
# After the run open the merged report:
#   VCS:     urg -dir cov_merge.vdb -report urgReport
#   Xcelium: imc -load cov_merge.cvd -gui   (or  xrun -covmerge)
RTL_A="../design/hang_prot_wskid.sv ../design/hang_prot_recover.sv \
../design/hang_prot_core.sv ../design/reg_wrap.sv ../design/hang_prot_regfile.sv \
../design/hang_prot_gen_wrap.sv ../design/hang_prot_mcu2main_mon.sv"
RTL_B="../design/hang_prot_wskid.sv ../design/hang_prot_bdry_in.sv \
../design/hang_prot_core.sv ../design/reg_wrap.sv ../design/hang_prot_regfile.sv \
../design/hang_prot_main2mcu_mon.sv"
COV=line+cond+fsm+tgl+assert

# ---------- VCS ----------
# vcs -full64 -sverilog -assert svaext -cm $COV -cm_dir cov_a.vdb \
#     $RTL_A ../tb_hang_prot_a_wrap.sv -o simv_a -l comp_a.log
# ./simv_a -cm $COV -cm_dir cov_a.vdb -l sim_a.log
# vcs -full64 -sverilog -assert svaext -cm $COV -cm_dir cov_b.vdb \
#     $RTL_B ../tb_hang_prot_b_wrap.sv -o simv_b -l comp_b.log
# ./simv_b -cm $COV -cm_dir cov_b.vdb -l sim_b.log
# urg -dir cov_a.vdb cov_b.vdb -merge cov_merge.vdb -report urgReport

# ---------- Xcelium ----------
# xrun -64bit -sv -assert -cm $COV -cm_name cov_a $RTL_A \
#     ../tb_hang_prot_a_wrap.sv -l comp_a.log -R -l sim_a.log
# xrun -64bit -sv -assert -cm $COV -cm_name cov_b $RTL_B \
#     ../tb_hang_prot_b_wrap.sv -l comp_b.log -R -l sim_b.log
# xrun -covmerge -out cov_merge.cvd cov_a.cvd cov_b.cvd
# xrun -covreport cov_merge.cvd

echo "edit this script to enable your simulator's block, then run"
