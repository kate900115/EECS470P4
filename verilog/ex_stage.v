//////////////////////////////////////////////////////////////////////////
//                                                                      //
//   Modulename :  ex_stage.v                                           //
//                                                                      //
//  Description :  instruction execute (EX) stage of the pipeline;      //
//                 given the instruction command code CMD, select the   //
//                 proper input A and B for the ALU, compute the result,// 
//                 and compute the condition for branches, and pass all //
//                 the results down the pipeline. MWB                   // 
//                                                                      //
//                                                                      //
//////////////////////////////////////////////////////////////////////////

//
// The ALU
//
// given the command code CMD and proper operands A and B, compute the
// result of the instruction
//
// This module is purely combinational
//
module alu(
    input [63:0] opa,
    input [63:0] opb,
    ALU_FUNC     func,

    output logic [63:0] result
  );

    // This function computes a signed less-than operation
  function signed_lt;
    input [63:0] a, b;

    if (a[63] == b[63]) 
      signed_lt = (a < b); // signs match: signed compare same as unsigned
    else
      signed_lt = a[63];   // signs differ: a is smaller if neg, larger if pos
  endfunction

  always_comb begin
    case (func)
      ALU_ADDQ:     result = opa + opb;
      ALU_SUBQ:     result = opa - opb;
      ALU_AND:      result = opa & opb;
      ALU_BIC:      result = opa & ~opb;
      ALU_BIS:      result = opa | opb;
      ALU_ORNOT:    result = opa | ~opb;
      ALU_XOR:      result = opa ^ opb;
      ALU_EQV:      result = opa ^ ~opb;
      ALU_SRL:      result = opa >> opb[5:0];
      ALU_SLL:      result = opa << opb[5:0];
      ALU_SRA:      result = (opa >> opb[5:0]) | ({64{opa[63]}} << (64 -
                              opb[5:0])); // arithmetic from logical shift
      ALU_CMPULT:   result = { 63'd0, (opa < opb) };
      ALU_CMPEQ:    result = { 63'd0, (opa == opb) };
      ALU_CMPULE:   result = { 63'd0, (opa <= opb) };
      ALU_CMPLT:    result = { 63'd0, signed_lt(opa, opb) };
      ALU_CMPLE:    result = { 63'd0, (signed_lt(opa, opb) || (opa == opb)) };
      default:      result = 64'hXXXX_XXXX_XXXX_XXXX;  // here only to force
                              // a combinational solution
                              // a casex would be better
    endcase
  end
endmodule // alu

//
// BrCond module
//
// Given the instruction code, compute the proper condition for the
// instruction; for branches this condition will indicate whether the
// target is taken.
//
// This module is purely combinational
//
module brcond(// Inputs
    input [63:0] opa,    // Value to check against condition
    input  [2:0] func,  // Specifies which condition to check

    output logic cond    // 0/1 condition result (False/True)
  );

  always_comb begin
  case (func[1:0])                              // 'full-case'  All cases covered, no need for a default
    2'b00: cond = (opa[0] == 0);                // LBC: (lsb(opa) == 0) ?
    2'b01: cond = (opa == 0);                    // EQ: (opa == 0) ?
    2'b10: cond = (opa[63] == 1);                // LT: (signed(opa) < 0) : check sign bit
    2'b11: cond = (opa[63] == 1) || (opa == 0);  // LE: (signed(opa) <= 0)
  endcase
  
     // negate cond if func[2] is set
    if (func[2])
    cond = ~cond;
  end
endmodule // brcond


module ex_stage(
    input          			clock,			// system clock
    input          			reset,			// system reset

    input  [3:0][63:0]			fu_rs_opa_in,		// register A value from reg file
    input  [3:0][63:0]			fu_rs_opb_in,		// register B value from reg file
    input  [3:0][$clog2(`PRF_SIZE)-1:0]	fu_rs_dest_tag_in,
    input  [3:0][$clog2(`ROB_SIZE)-1:0]	fu_rs_rob_idx_in,
    input  [3:0][5:0]  			fu_rs_op_type_in,	// incoming instruction
    input  [3:0]			fu_rs_valid_in,
    ALU_FUNC [5:0]     			fu_alu_func_in,	// ALU function select from decoder

    //input          id_ex_cond_branch,   // is this a cond br? from decoder
    //input          id_ex_uncond_branch, // is this an uncond br? from decoder

    input	adder1_send_in_success,
    input	adder2_send_in_success,
    input	mult1_send_in_success,
    input	mult2_send_in_success,

    //output	ex_take_branch_out,  // is this a taken branch?

    output logic [3:0][$clog2(`PRF_SIZE)-1:0]	fu_rs_dest_tag_out,
    output logic [3:0][$clog2(`ROB_SIZE)-1:0]	fu_rs_rob_idx_out,
    output logic [3:0][5:0]  			fu_rs_op_type_out,	// incoming instruction
    output ALU_FUNC [3:0]			fu_alu_func_out,	// ALU function select from decoder
    output logic [3:0][63:0]			fu_result_out,
    output logic [3:0]				fu_result_is_valid,	// 0,2: mult1,2; 1,3: adder1,2
    output logic [3:0]				fu_is_available
/*
    output logic [$clog2(`PRF_SIZE)-1:0]	fu_rs_dest_tag_out1,
    output logic [$clog2(`ROB_SIZE)-1:0]	fu_rs_rob_idx_out1,
    output logic [5:0]  			fu_rs_op_type_out1,	// incoming instruction
    output ALU_FUNC				fu_alu_func_out1,	// ALU function select from decoder
    output logic [63:0]				fu_result1,
    output logic				fu_is_valid1,
*/
  );

	logic		brcond_result;
	logic  [63:0]	mult_result1;
	logic  [63:0]	mult_result2;
	logic		mult_done1;
	logic		mult_done2;
	logic  [63:0]	alu_result1;
	logic  [63:0]	alu_result2;
	logic  [5:0]	internal_fu_value_select1;
	logic  [5:0]	internal_fu_value_select2;
	logic  [3:0]	fu_is_in_use;

	//assign ex_take_branch_out = id_ex_uncond_branch | (id_ex_cond_branch & brcond_result);

   // fu1: multipler1
	mult #(.stage(4)) mult1(// Inputs
		.clock(clock),
		.reset(reset),
		.mcand(fu_rs_opa_in[0]),
		.mplier(fu_rs_opb_in[0]),
		.start(fu_rs_valid_in[0]),
	// Outputs
		.product(mult_result1),
		.done(mult_done1)
	);

    // fu2: ALU1
	alu alu1 (// Inputs
		.opa(fu_rs_opa_in[1]),
		.opb(fu_rs_opb_in[1]),
		.func(fu_alu_func_in[1]),
    // Output
		.result(alu_result1)
	);

   // fu3: multipler2
	mult #(.stage(4)) mult2(// Inputs
		.clock(clock),
		.reset(reset),
		.mcand(fu_rs_opa_in[2]),
		.mplier(fu_rs_opb_in[2]),
		.start(fu_rs_valid_in[2]),
	// Outputs
		.product(mult_result2),
		.done(mult_done2)
	);

    // fu4: ALU2
	alu alu2 (// Inputs
		.opa(fu_rs_opa_in[3]),
		.opb(fu_rs_opb_in[3]),
		.func(fu_alu_func_in[3]),
    // Output
		.result(alu_result2)
	);

   //
   // instantiate the branch condition tester
   //
	//brcond brcond (// Inputs
	//.opa(id_ex_rega),       // always check regA value
	//.func(id_ex_IR[28:26]), // inst bits to determine check
	    // Output
	//.cond(brcond_result)
	//);

   // ultimate "take branch" signal:
   //    unconditional, or conditional and the condition is true
	assign fu_is_available[0] = fu_result_is_valid[0] ? mult1_send_in_success  : ~fu_is_in_use[0];
	assign fu_is_available[1] = fu_result_is_valid[1] ? adder1_send_in_success : ~fu_is_in_use[1];
	assign fu_is_available[2] = fu_result_is_valid[2] ? mult2_send_in_success  : ~fu_is_in_use[2];
	assign fu_is_available[3] = fu_result_is_valid[3] ? adder2_send_in_success : ~fu_is_in_use[3];
	always_ff @(posedge clock)
	begin
		if (reset) 
		begin
			fu_rs_dest_tag_out[0]	<= `SD 0;
			fu_rs_rob_idx_out[0]	<= `SD 0;
			fu_rs_op_type_out[0]	<= `SD 0;
			fu_alu_func_out[0]	<= `SD ALU_DEFAULT;
			fu_result_is_valid[0]	<= `SD 1'b0;
			fu_result_out[0]	<= `SD 0;
			fu_is_in_use[0]		<= `SD 1'b0;
			
			fu_rs_dest_tag_out[1]	<= `SD 0;
			fu_rs_rob_idx_out[1]	<= `SD 0;
			fu_rs_op_type_out[1]	<= `SD 0;
			fu_alu_func_out[1]	<= `SD ALU_DEFAULT;
			fu_result_is_valid[1]	<= `SD 1'b0;
			fu_result_out[1]	<= `SD 0;
			fu_is_in_use[1]		<= `SD 1'b0;

			fu_rs_dest_tag_out[2]	<= `SD 0;
			fu_rs_rob_idx_out[2]	<= `SD 0;
			fu_rs_op_type_out[2]	<= `SD 0;
			fu_alu_func_out[2]	<= `SD ALU_DEFAULT;
			fu_result_is_valid[2]	<= `SD 1'b0;
			fu_result_out[2]	<= `SD 0;
			fu_is_in_use[2]		<= `SD 1'b0;

			fu_rs_dest_tag_out[3]	<= `SD 0;
			fu_rs_rob_idx_out[3]	<= `SD 0;
			fu_rs_op_type_out[3]	<= `SD 0;
			fu_alu_func_out[3]	<= `SD ALU_DEFAULT;
			fu_result_is_valid[3]	<= `SD 1'b0;
			fu_result_out[3]	<= `SD 0;
			fu_is_in_use[3]		<= `SD 1'b0;
		end
		else begin
			if (fu_rs_valid_in[0])
			begin
				fu_rs_dest_tag_out[0]	<= `SD fu_rs_dest_tag_in[0];
				fu_rs_rob_idx_out[0]	<= `SD fu_rs_rob_idx_in[0];
				fu_rs_op_type_out[0]	<= `SD fu_rs_op_type_in[0];
				fu_alu_func_out[0]	<= `SD fu_alu_func_in[0];
				fu_result_is_valid[0]	<= `SD 1'b0;
				fu_is_in_use[0]		<= `SD 1'b1;
			end
			else if (mult_done1) begin
				fu_result_out[0]	<= `SD mult_result1;
				fu_result_is_valid[0]	<= `SD 1'b1;
				fu_is_in_use[0]		<= `SD 1'b0;
			end
			else if (mult1_send_in_success) begin
				fu_result_is_valid[0]	<= `SD 1'b0;
			end
			
			if (fu_rs_valid_in[1])
			begin
				fu_rs_dest_tag_out[1]	<= `SD fu_rs_dest_tag_in[1];
				fu_rs_rob_idx_out[1]	<= `SD fu_rs_rob_idx_in[1];
				fu_rs_op_type_out[1]	<= `SD fu_rs_op_type_in[1];
				fu_alu_func_out[1]	<= `SD fu_alu_func_in[1];
				fu_result_out[1]	<= `SD alu_result1;
				fu_result_is_valid[1]	<= `SD 1'b1;
			end
			else if (adder1_send_in_success)
			begin
				fu_result_is_valid[1]	<= `SD 1'b0;
			end

			if (fu_rs_valid_in[2])
			begin
				fu_rs_dest_tag_out[2]	<= `SD fu_rs_dest_tag_in[2];
				fu_rs_rob_idx_out[2]	<= `SD fu_rs_rob_idx_in[2];
				fu_rs_op_type_out[2]	<= `SD fu_rs_op_type_in[2];
				fu_alu_func_out[2]	<= `SD fu_alu_func_in[2];
				fu_result_is_valid[2]	<= `SD 1'b0;
				fu_is_in_use[2]		<= `SD 1'b1;
			end
			else if (mult_done2) begin
				fu_result_out[2]	<= `SD mult_result2;
				fu_result_is_valid[2]	<= `SD 1'b1;
				fu_is_in_use[2]		<= `SD 1'b0;
			end
			else if (mult2_send_in_success) begin
				fu_result_is_valid[2]	<= `SD 1'b0;
			end
			
			if (fu_rs_valid_in[3])
			begin
				fu_rs_dest_tag_out[3]	<= `SD fu_rs_dest_tag_in[3];
				fu_rs_rob_idx_out[3]	<= `SD fu_rs_rob_idx_in[3];
				fu_rs_op_type_out[3]	<= `SD fu_rs_op_type_in[3];
				fu_alu_func_out[3]	<= `SD fu_alu_func_in[3];
				fu_result_out[3]	<= `SD alu_result2;
				fu_result_is_valid[3]	<= `SD 1'b1;
			end
			else if (adder2_send_in_success)
			begin
				fu_result_is_valid[3]	<= `SD 1'b0;
			end
		end
	end

endmodule // module ex_stage
