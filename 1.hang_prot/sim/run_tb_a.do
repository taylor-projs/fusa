# run_tb_a.do - Questa/ModelSim: SCENARIO 2 (hang_prot_mcu2main_mon)
# usage (from sim/):  vsim -c -do run_tb_a.do
# coverage: statement/branch/condition/fsm/toggle -> cov_a.ucdb
onerror {quit -f}
quit -sim

vlib work_a
vmap work work_a

vlog -sv -cover bsftc \
    ../rtl/hang_prot_wskid.sv \
    ../rtl/hang_prot_recover.sv \
    ../rtl/hang_prot_core.sv \
    ../../common_modules/reg_wrap.sv \
    ../rtl/hang_prot_regfile.sv \
    ../rtl/hang_prot_top.sv \
    ../rtl/hang_prot_mcu2main_top.sv \
    ../tb_hang_prot_a_wrap.sv

vsim -coverage -c work_a.tb_hang_prot_a_wrap
add wave -recursive *
run -all
coverage save cov_a.ucdb
quit -f
