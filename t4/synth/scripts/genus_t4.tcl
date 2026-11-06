set RTL_PATH		"../../"
set LIB_PATH 		"../lib/"
set LEF_PATH		"../lef/scaled/"
set TLEF_PATH		"../techlef/"
set QRC_PATH 		"../qrc/"
set SDC_PATH		"../constraints/"
set OUT_PATH		"../outputs/"
set REP_PATH		"../reports/"
set DESIGN 		"ps2_driver"

set LIB_LIST {  asap7sc7p5t_AO_LVT_TT_nldm_211120.lib   asap7sc7p5t_INVBUF_LVT_TT_nldm_220122.lib   asap7sc7p5t_OA_LVT_TT_nldm_211120.lib   asap7sc7p5t_SEQ_LVT_TT_nldm_220123.lib   asap7sc7p5t_SIMPLE_LVT_TT_nldm_211120.lib }

set LEF_LIST { asap7_tech_4x_201209.lef asap7sc7p5t_28_L_4x_220121a.lef asap7sc7p5t_28_R_4x_220121a.lef asap7sc7p5t_28_SL_4x_220121a.lef}

set QRC_FILE "qrcTechFile_typ03_scaled4xV06"

set RTL_LIST {ps2_driver.sv}

set_db init_lib_search_path "$LIB_PATH $LEF_PATH $TLEF_PATH"
set_db init_hdl_search_path $RTL_PATH
set_db / .library "$LIB_LIST"
set_db lef_library "$LEF_LIST"
set_db qrc_tech_file "$QRC_PATH/$QRC_FILE"

set_db lp_insert_clock_gating true

read_hdl -sv ${RTL_LIST}
elaborate $DESIGN
check_design -unresolved
read_sdc $SDC_PATH/$DESIGN.sdc

syn_generic
syn_map
syn_opt
write_hdl > $OUT_PATH/$DESIGN.netlist.v
write_sdc > $OUT_PATH/$DESIGN.sdc

report_area
report_timing -fields "timing_point cell delay arrival"
report_power -unit mW -format %.4f

report clocks       > $REP_PATH/$DESIGN.clocks.rep
report timing -lint > $REP_PATH/$DESIGN.lint.rep
report timing       > $REP_PATH/$DESIGN.timing.rep
report timing -from [all_registers] -to [all_registers] > $REP_PATH/$DESIGN.timing_reg2reg.rep
report area         > $REP_PATH/$DESIGN.area.rep
report gates        > $REP_PATH/$DESIGN.gates.rep
report power        > $REP_PATH/$DESIGN.power.rep
report clock_gating > $REP_PATH/$DESIGN.clock_gating.rep
