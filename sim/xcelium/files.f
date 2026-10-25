// =============================================================================
// files.f  -  file list for Xcelium (xrun -f sim/xcelium/files.f)
//
// Paths are relative to the REPOSITORY ROOT (run xrun from there).
// Compile options (-define FAULT_INJECT, -incdir rtl/include) are passed by
// run_xcelium.sh, not here.
// =============================================================================

// ---------------- RTL (design) ----------------
rtl/sram_array.v
rtl/fault_injector.v
rtl/spare_icg.v
rtl/spare_row_bank.v
rtl/sram_wrapper.v
rtl/march_cminus.v
rtl/fault_logger.v
rtl/bira.v
rtl/repair_table.v
rtl/remap_unit.v
rtl/bisr_ctrl_fsm.v
rtl/shared_bisr_top.v
rtl/dedicated_bisr_top.v
rtl/clustered_bisr_top.v

// ---------------- Testbenches ----------------
tb/tb_bisr_compare.v
tb/tb_top_scenarios.v
tb/tb_sram_injector.v
tb/tb_march.v
tb/tb_logger.v
tb/tb_bira.v
tb/tb_remap.v
