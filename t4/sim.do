if {[ file exists work ]} {
    vdel -lib work -all
}

vlib work

vlog -sv ps2_driver.sv
vlog -sv ps2_driver_if.sv
vlog -sv tb.sv

vsim -voptargs=+acc -onfinish stop work.tb -l out.log

run -all
