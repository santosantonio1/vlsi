# ps2_driver constraints. Units follow the ASAP7 libs: ps, fF.

set CLK_PERIOD 10000    ;# clock_in = 100 MHz (spec item 4)

create_clock -name clock_in -period $CLK_PERIOD [get_ports clock_in]
set_clock_uncertainty 100 [get_clocks clock_in]
set_clock_transition  20  [get_clocks clock_in]

# 30% of the period for logic outside the block, as in lab 2
set_input_delay  -clock clock_in [expr 0.3 * $CLK_PERIOD] [get_ports {reset_in clock_ps2 data_ps2}]
set_output_delay -clock clock_in [expr 0.3 * $CLK_PERIOD] [all_outputs]

# clock_ps2/data_ps2 come from the keyboard, asynchronous to clock_in, and enter a 2-FF synchronizer
set_false_path -from [get_ports {clock_ps2 data_ps2}]

set_driving_cell -lib_cell BUFx2_ASAP7_75t_L [get_ports {reset_in clock_ps2 data_ps2}]
set_load 2 [all_outputs]
