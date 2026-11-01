# run_tb_b.do - Questa/ModelSim: SCENARIO 1 (hang_prot_main2mcu_mon)
# usage (from sim/):  vsim -c -do run_tb_b.do
# coverage: statement/branch/condition/fsm/toggle -> cov_b.ucdb
onerror {quit -f}
quit -sim

vlib work_b
vmap work work_b

vlog -sv -cover bsftc \
    ../design/hang_prot_wskid.sv \
    ../design/hang_prot_bdry_in.sv \
    ../design/hang_prot_core.sv \
    ../design/reg_wrap.sv \
    ../design/hang_prot_regfile.sv \
    ../design/hang_prot_main2mcu_mon.sv \
    ../tb_hang_prot_b_wrap.sv

vsim -coverage -c work_b.tb_hang_prot_b_wrap
add wave -recursive *
run -all
coverage save cov_b.ucdb
quit -f
