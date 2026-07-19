#**************************************************************
# Timing Constraints — SNN FPGA Accelerator (top.v)
#**************************************************************
# Place this file in your Quartus project directory as timing.sdc
# Quartus will pick it up automatically if it matches your project
# name, OR add it explicitly via:
#   Assignments -> Settings -> TimeQuest Timing Analyzer -> SDC File
#**************************************************************

#--------------------------------------------------------------
# Base clock
#--------------------------------------------------------------
# Adjust -period to your target clock speed (in ns).
# 10.000 ns = 100 MHz. Start conservative (e.g. 20.000 = 50 MHz)
# if you're not sure your design will meet 100 MHz yet — TimeQuest
# will report the actual achievable Fmax regardless of what you
# constrain for, so this number is a target, not a hard limit.
create_clock -name clk -period 30.000 [get_ports clk]

# Recommended: models realistic clock jitter/skew so Fmax numbers
# aren't overly optimistic
derive_clock_uncertainty

#--------------------------------------------------------------
# Asynchronous reset — not a timing path, exclude from analysis
#--------------------------------------------------------------
set_false_path -from [get_ports reset_n]

#--------------------------------------------------------------
# Control/status ports — these are slow, human/testbench-driven
# signals (not part of a high-speed interface), so treat them as
# false paths rather than trying to meet register-to-pin timing.
#--------------------------------------------------------------
set_false_path -from [get_ports start]
set_false_path -to   [get_ports done]
set_false_path -to   [get_ports predicted_class]

#--------------------------------------------------------------
# input_spikes — ONLY include this if input_spikes is still a
# top-level port in your design. If you've since moved image
# loading to an internal BRAM (recommended, to fix the pin-count
# error), delete this line — there's no top-level port left to
# constrain.
#--------------------------------------------------------------
set_false_path -from [get_ports {input_spikes[*]}]
