if {[ file exists work ]} {
    vdel -lib work -all
}

vlib work

vlog -sv receptor_padrao.sv
vlog -sv receptor_padrao_if.sv
vlog -sv tb.sv

vsim -voptargs=+acc -onfinish stop work.tb -l out.log

run 100 ns
