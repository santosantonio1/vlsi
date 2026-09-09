onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /reg_bank_tb/clk
add wave -noupdate /reg_bank_tb/vif/clk
add wave -noupdate /reg_bank_tb/vif/rst
add wave -noupdate /reg_bank_tb/vif/rd_en
add wave -noupdate /reg_bank_tb/vif/wr_en
add wave -noupdate /reg_bank_tb/vif/rd_address
add wave -noupdate /reg_bank_tb/vif/wr_data
add wave -noupdate /reg_bank_tb/vif/wr_address
add wave -noupdate /reg_bank_tb/vif/rd_data
add wave -noupdate /reg_bank_tb/cuv/clk
add wave -noupdate /reg_bank_tb/cuv/rd_en
add wave -noupdate /reg_bank_tb/cuv/rst
add wave -noupdate /reg_bank_tb/cuv/wr_en
add wave -noupdate /reg_bank_tb/cuv/rd_data
add wave -noupdate /reg_bank_tb/cuv/rd_address
add wave -noupdate /reg_bank_tb/cuv/wr_data
add wave -noupdate /reg_bank_tb/cuv/wr_address
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {347 ns} 0}
quietly wave cursor active 1
configure wave -namecolwidth 243
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {26 ns} {241 ns}
