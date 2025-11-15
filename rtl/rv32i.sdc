set_units -time ns
# constraints.sdc for rv32i_top

# Define the primary clock (100 MHz = 10ns period)
create_clock -name clk_i -period 10 [get_ports clk_i]

# Input delay assumptions (data arriving 2ns after clock edge)
set_input_delay 2 -clock clk_i [all_inputs]

# Output delay assumptions (data required 2ns before next clock edge)
set_output_delay 2 -clock clk_i [all_outputs]

# False path for reset (not part of timing)
set_false_path -from [get_ports resetn_i]
