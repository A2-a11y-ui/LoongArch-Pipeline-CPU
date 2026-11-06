## Optional 100 MHz clock constraint for EGO1.
## Add this file only if no other active XDC already creates a clock on port clk.
create_clock -name ego1_sys_clk -period 10.000 [get_ports {clk}]
