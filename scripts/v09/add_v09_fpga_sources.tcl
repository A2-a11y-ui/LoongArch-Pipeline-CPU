# V0.9 FPGA integration helper for the existing Vivado 2019.1 project.
#
# Usage:
#   1. Open build/loongarch_cpu_v09_fpga/loongarch_cpu_v09_fpga.xpr.
#   2. In the Vivado Tcl Console, run:
#      source D:/CPU_Project/LoongArch-Pipeline-CPU/scripts/v09/add_v09_fpga_sources.tcl
#
# The repository root is derived from this script's own location.
# Existing source files are not overwritten. Existing clock constraints are
# left untouched; add ego1_v09_clock.xdc manually only if no clk clock exists.

if {[current_project -quiet] eq ""} {
    error "Open the loongarch_cpu_v09_fpga Vivado project before running this script."
}

set script_path [file normalize [info script]]
set script_dir  [file dirname $script_path]
set repo_root   [file normalize [file join $script_dir .. ..]]
set project_dir [file normalize [get_property DIRECTORY [current_project]]]

proc add_once {fileset_name path} {
    set abs_path [file normalize $path]
    if {![file exists $abs_path]} {
        error "Required V0.9 file not found: $abs_path"
    }

    set fs_obj [get_filesets $fileset_name]
    set matches [get_files -quiet -of_objects $fs_obj $abs_path]

    if {[llength $matches] == 0} {
        add_files -norecurse -fileset $fileset_name $abs_path
        puts "Added to $fileset_name: $abs_path"
    } else {
        puts "Already present in $fileset_name: $abs_path"
    }
}

# Required existing RTL dependencies. Files already present in sources_1
# are detected and are not added a second time.
set design_relpaths [list \
    rtl/common/cpu_defs.vh \
    rtl/common/pc_if_controller.v \
    rtl/common/pipeline_control_unit.v \
    rtl/common/if_id_reg.v \
    rtl/common/id_ex_reg.v \
    rtl/common/ex_mem_reg.v \
    rtl/common/mem_wb_reg.v \
    rtl/common/decoder.v \
    rtl/common/regfile.v \
    rtl/common/forwarding_unit.v \
    rtl/common/load_use_hazard_unit.v \
    rtl/memory_cache/imm_gen.v \
    rtl/memory_cache/dmem_latency.v \
    rtl/memory_cache/icache_if_adapter.v \
    rtl/memory_cache/icache_2way_latency.v \
    rtl/alu_branch/alu.v \
    rtl/alu_branch/mdu_iterative.v \
    rtl_test_only/branch_resolve_v04.v \
    rtl_test_only/mdu_decode_v08.v \
    rtl_test_only/pipeline_cpu_core_v08_mdu_datapath.v \
    rtl/fpga/imem_bram.v \
    rtl/fpga/pipeline_cpu_fpga.v \
    rtl/fpga/ego1_top.v \
]

foreach relpath $design_relpaths {
    add_once sources_1 [file join $repo_root $relpath]
}

# Copy the program image beside the .xpr so the readmemh path is independent
# of the simulator/synthesis run directory.
set mem_src [file normalize [file join $repo_root rtl fpga fpga_demo.mem]]
set mem_dst [file normalize [file join $project_dir fpga_demo.mem]]
if {![file exists $mem_src]} {
    error "Program image not found: $mem_src"
}
file copy -force $mem_src $mem_dst
add_once sources_1 $mem_dst

set mem_obj [get_files -quiet -of_objects [get_filesets sources_1] $mem_dst]
if {[llength $mem_obj] > 0} {
    set_property file_type {Memory Initialization Files} $mem_obj
    set_property used_in_synthesis true $mem_obj
    set_property used_in_simulation true $mem_obj
}

# Board pin assignments. The existing icache_timing.xdc is not modified.
add_once constrs_1 [file join $repo_root rtl fpga ego1_v09_pins.xdc]

# Add the optional 100 MHz clock constraint only when the project has no
# create_clock command that targets the top-level clk port.
set clock_already_defined 0
foreach xdc_obj [get_files -quiet -of_objects [get_filesets constrs_1]] {
    set xdc_name [get_property NAME $xdc_obj]
    if {[file exists $xdc_name]} {
        set fh [open $xdc_name r]
        set xdc_text [read $fh]
        close $fh
        if {[regexp -nocase {create_clock[^\n]*get_ports[^\n]*clk} $xdc_text]} {
            set clock_already_defined 1
        }
    }
}
if {!$clock_already_defined} {
    add_once constrs_1 [file join $repo_root rtl fpga ego1_v09_clock.xdc]
} else {
    puts "Existing create_clock for port clk found; optional clock XDC was not added."
}

# Add the new wrapper-level regression as the active simulation top.
set tb_path [file join $repo_root tb pipeline_cpu tb_pipeline_cpu_v09_fpga_smoke.v]
add_once sim_1 $tb_path

# Use an absolute memory path for both synthesis and simulation generics.
set mem_path_for_hdl [string map {\\ /} $mem_dst]
# Do not embed Verilog quote characters in the generic value.
# Vivado 2019.1 synthesis passes the value to $readmemh verbatim; embedded
# quotes become part of the filename and cause Synth 8-4445.
set mem_generic [format {IMEM_FILE=%s} $mem_path_for_hdl]

set_property top ego1_top [get_filesets sources_1]
set_property generic $mem_generic [get_filesets sources_1]

set_property top tb_pipeline_cpu_v09_fpga_smoke [get_filesets sim_1]
set_property generic $mem_generic [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "------------------------------------------------------------"
puts "V0.9 FPGA sources configured."
puts "Synthesis top : ego1_top"
puts "Simulation top: tb_pipeline_cpu_v09_fpga_smoke"
puts "Program image : $mem_dst"
puts "Next: Run Simulation > Run Behavioral Simulation."
puts "Do not generate/program the bitstream until the smoke test passes."
puts "------------------------------------------------------------"
