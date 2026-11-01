# run_tb_a.do - Questa/ModelSim: SCENARIO 2 (hang_prot_mcu2main_mon)
# usage (from sim/):  vsim -c -do run_tb_a.do
# coverage: statement/branch/condition/fsm/toggle -> cov_a.ucdb
onerror {quit -f}
quit -sim

vlib work_a
vmap work work_a

vlog -sv -cover bsftc \
    ../design/hang_prot_wskid.sv \
    ../design/hang_prot_recover.sv \
    ../design/hang_prot_core.sv \
    ../design/reg_wrap.sv \
    ../design/hang_prot_regfile.sv \
    ../design/hang_prot_gen_wrap.sv \
    ../design/hang_prot_mcu2main_mon.sv \
    ../tb_hang_prot_a_wrap.sv

vsim -coverage -c work_a.tb_hang_prot_a_wrap
add wave -recursive *
run -all
coverage save cov_a.ucdb
quit -f
