cd "C:/SNN_FPGA_Accelerator"
vlib ./work
vmap work ./work
vlog -work work rtl/pe.v tb/tb_pe.v
vsim -voptargs="+acc" work.tb_pe
add wave -position insertpoint sim:/tb_pe/*
run -all                每次重启modelsim的时候需要用到