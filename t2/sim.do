quit -sim

if {[file exists work]} {
    vdel -lib work -all
}

vlib work

vcom  reg_bank.vhd
vlog -sv reg_bank_if.sv
vlog -sv reg_bank_tb.sv

vsim -t ps -voptargs=+acc -onfinish stop -wlfdeleteonquit work.reg_bank_tb -l out.txt 

add wave sim:vif/*

run -all

exit