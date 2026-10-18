//============================================================================
// bisr_defines.vh
// Shared constants for the Shared BISR project.
//
// Default architecture parameters live on each module (and are passed down
// from shared_bisr_top / dedicated_bisr_top); this file only holds codes that
// RTL and testbenches must agree on.
//============================================================================
`ifndef BISR_DEFINES_VH
`define BISR_DEFINES_VH

// ---------------------------------------------------------------------------
// Fault types understood by fault_injector (simulation only)
// ---------------------------------------------------------------------------
`define FT_SA0      0   // stuck-at-0: cell always reads/stores 0
`define FT_SA1      1   // stuck-at-1: cell always reads/stores 1
`define FT_TF_UP    2   // transition fault: cell cannot make a 0 -> 1 transition
`define FT_TF_DOWN  3   // transition fault: cell cannot make a 1 -> 0 transition

// ---------------------------------------------------------------------------
// Fault-injection targets (testbench only)
// ---------------------------------------------------------------------------
`define TGT_MAIN    0   // a row of a main SRAM array
`define TGT_LOCAL   1   // a local spare row of one SRAM
`define TGT_GLOBAL  2   // a row of the shared global spare pool

// ---------------------------------------------------------------------------
// Fault-class bits stored by fault_logger (derived from the March element)
// ---------------------------------------------------------------------------
// bit 0 : cell read 1 where 0 was expected  (SA1 or down-transition fault)
// bit 1 : cell read 0 where 1 was expected  (SA0 or up-transition fault)

`endif
