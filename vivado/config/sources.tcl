# CLAUDED
# ---------------------------------------------------------------------------
# What goes into the project. Paths/globs are relative to the repo root.
# Edit this file, re-run caravel_generate.tcl, and the project is rebuilt.
# ---------------------------------------------------------------------------

# --- Design sources (-> sources_1: synthesis AND simulation) ---------------
# Groups are only for readability; they are all added to sources_1.
set rtl_groups [dict create \
    caravel         {rtl/caravel/*.v} \
    userspace       {rtl/userspace/*.v} \
    synaptic_module {rtl/synaptic_module/*.v} \
    sigmoid_lut     {rtl/sigmoid_lut/*.v} \
    dma             {rtl/dma/*.v} \
    memory          {rtl/memory/*.v} \
    sd_card         {rtl/sd_card_interface/*.v} \
    seven_segment   {rtl/seven_segment/*.v} \
]

# Globs to drop from the groups above.
# NOTE: these are my best reading of the repo -- check them against your design.
set rtl_exclude {
    rtl/caravel/io_buf*copy.v
    rtl/caravel/caravel_netlists.v
    rtl/caravel/openframe_netlists.v
    rtl/caravel/caravel_openframe.v
    rtl/caravel/constant_block_antmicro.v
}
# io_buf copy.v      : defines module io_buf a second time (duplicate of io_buf.v)
# *_netlists.v       : only `include sky130 / gate-level files that aren't in the repo
# caravel_openframe  : module isn't instantiated anywhere

# Directories searched for `include "..."` (applies to sources_1 and every simset).
set include_dirs {rtl/caravel rtl/userspace}

# --- Simulation suites (-> one simulation fileset each: sim_<name>) --------
# A simset always sees ALL of sources_1 as well (Vivado has no way to hide it),
# so a suite only lists what is *extra*:
#   files    testbench files (globs)
#   top      default top module for `launch_simulation`
#   extra    sim-only models that must not be synthesized (flash model, etc.)
#   defines  verilog `define values for this suite only
#   runtime  xsim run length ("-all", "10us", ...)
set sim_suites [dict create]

dict set sim_suites synaptic_module {
    files   {testbenches/synaptic_module/*.v}
    top     tb_SynapticModule_Standalone
    extra   {}
    defines {}
    runtime -all
}
dict set sim_suites lut {
    files   {testbenches/sigmoid_lut/LUTBugSimulation_tb.v
             testbenches/sigmoid_lut/LUTBugSimulation3_tb.v}
    top     LUTBugSimulation_tb
    extra   {}
    defines {}
    runtime -all
}
# Own suite on purpose: this testbench file also defines `module bram`, which
# would collide with the bram IP that lives in sources_1.
dict set sim_suites lut_bug2 {
    files   {testbenches/sigmoid_lut/LUTBugSimulation2_tb.v}
    top     LUTBugSimulation2_tb
    extra   {}
    defines {}
    runtime -all
}
dict set sim_suites sd_card {
    files   {testbenches/sd_card_interface/external_sdCard_tb.v}
    top     external_sdCard_tb
    extra   {}
    defines {}
    runtime -all
}
dict set sim_suites userspace {
    files   {testbenches/userspace/TopLevel_tb.v}
    top     TopLevel_tb
    extra   {}
    defines {}
    runtime -all
}
dict set sim_suites caravel_full {
    files   {testbenches/caravel/gpio_mgmt_tb.v}
    top     gpio_mgmt_tb
    extra   {}
    defines {}
    runtime -all
}

# Which simset is active when you open the project.
set default_suite synaptic_module