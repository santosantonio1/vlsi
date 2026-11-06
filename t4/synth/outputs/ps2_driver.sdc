# ####################################################################

#  Created by Genus(TM) Synthesis Solution 21.12-s068_1 on Fri Nov 06 19:41:26 -03 2026

# ####################################################################

set sdc_version 2.0

set_units -capacitance 1fF
set_units -time 1ps

# Set the current design
current_design ps2_driver

create_clock -name "clock_in" -period 10000.0 -waveform {0.0 5000.0} [get_ports clock_in]
set_clock_transition 20.0 [get_clocks clock_in]
set_load -pin_load 2.0 [get_ports {data_p[7]}]
set_load -pin_load 2.0 [get_ports {data_p[6]}]
set_load -pin_load 2.0 [get_ports {data_p[5]}]
set_load -pin_load 2.0 [get_ports {data_p[4]}]
set_load -pin_load 2.0 [get_ports {data_p[3]}]
set_load -pin_load 2.0 [get_ports {data_p[2]}]
set_load -pin_load 2.0 [get_ports {data_p[1]}]
set_load -pin_load 2.0 [get_ports {data_p[0]}]
set_load -pin_load 2.0 [get_ports data_p_en]
set_false_path -from [list \
  [get_ports clock_ps2]  \
  [get_ports data_ps2] ]
group_path -weight 1.000000 -name cg_enable_group_clock_in -through [list \
  [get_pins RC_CG_HIER_INST0/enable]  \
  [get_pins RC_CG_HIER_INST0/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST1/enable]  \
  [get_pins RC_CG_HIER_INST1/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST2/enable]  \
  [get_pins RC_CG_HIER_INST2/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST3/enable]  \
  [get_pins RC_CG_HIER_INST3/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST0/enable]  \
  [get_pins RC_CG_HIER_INST0/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST1/enable]  \
  [get_pins RC_CG_HIER_INST1/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST2/enable]  \
  [get_pins RC_CG_HIER_INST2/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST3/enable]  \
  [get_pins RC_CG_HIER_INST3/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST0/enable]  \
  [get_pins RC_CG_HIER_INST0/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST1/enable]  \
  [get_pins RC_CG_HIER_INST1/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST2/enable]  \
  [get_pins RC_CG_HIER_INST2/RC_CGIC_INST/ENA]  \
  [get_pins RC_CG_HIER_INST3/enable]  \
  [get_pins RC_CG_HIER_INST3/RC_CGIC_INST/ENA] ]
set_clock_gating_check -setup 0.0 
set_input_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports reset_in]
set_input_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports clock_ps2]
set_input_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports data_ps2]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[7]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[6]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[5]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[4]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[3]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[2]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[1]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports {data_p[0]}]
set_output_delay -clock [get_clocks clock_in] -add_delay 3000.0 [get_ports data_p_en]
set_driving_cell -lib_cell BUFx2_ASAP7_75t_L -library asap7sc7p5t_INVBUF_LVT_TT_nldm_211120 -pin "Y" [get_ports reset_in]
set_driving_cell -lib_cell BUFx2_ASAP7_75t_L -library asap7sc7p5t_INVBUF_LVT_TT_nldm_211120 -pin "Y" [get_ports clock_ps2]
set_driving_cell -lib_cell BUFx2_ASAP7_75t_L -library asap7sc7p5t_INVBUF_LVT_TT_nldm_211120 -pin "Y" [get_ports data_ps2]
set_clock_uncertainty -setup 100.0 [get_clocks clock_in]
set_clock_uncertainty -hold 100.0 [get_clocks clock_in]
