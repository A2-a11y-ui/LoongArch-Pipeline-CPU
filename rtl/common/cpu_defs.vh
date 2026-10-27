
`ifndef CPU_DEFS_VH
`define CPU_DEFS_VH

// CPU internal ALU operation codes
// These are NOT LoongArch instruction encodings.

`define ALU_ADD     4'h0
`define ALU_SUB     4'h1
`define ALU_AND     4'h2
`define ALU_OR      4'h3
`define ALU_XOR     4'h4
`define ALU_NOR     4'h5

`define ALU_SLT     4'h6
`define ALU_SLTU    4'h7

`define ALU_SLL     4'h8
`define ALU_SRL     4'h9
`define ALU_SRA     4'hA

`define ALU_PASS_B  4'hB

`endif