
//////////////////////////////////
//								//
//		  LSQ					//
//								//
//////////////////////////////////


module lsq(
	input	clock,
	input	reset,
	
	input  [63:0]								lsq_cdb1_in,     		// CDB bus from functional units 
	input  [$clog2(`PRF_SIZE)-1:0]  			lsq_cdb1_tag,    		// CDB tag bus from functional units 
	input										lsq_cdb1_valid,  		// The data on the CDB is valid 
	input  [63:0]								lsq_cdb2_in,     		// CDB bus from functional units 
	input  [$clog2(`PRF_SIZE)-1:0]  			lsq_cdb2_tag,    		// CDB tag bus from functional units 
	input										lsq_cdb2_valid,  		// The data on the CDB is valid 
	
    //for instruction1
   	input										inst1_valid,
	input	[5:0]								inst1_op_type,
	input	[63:0]								inst1_pc,
	input	[31:0]								inst1_in,
	input	[63:0] 								lsq_opa_in1,      	// Operand a from Rename  data
	input	[63:0] 								lsq_opb_in1,      	// Operand a from Rename  tag or data from prf
	input         								lsq_opb_valid1,   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
	input	[$clog2(`ROB_SIZE):0]				lsq_rob_idx_in1,  	// The rob index of instruction 1
	input	[4:0]								dest_reg_idx1,		//`none_reg if store

    //for instruction2
   	input										inst2_valid,
   	input	[5:0]								inst2_op_type,
	input	[63:0]								inst2_pc,
	input	[31:0]								inst2_in,
	input	[63:0] 								lsq_opa_in2,      	// Operand a from Rename  data
	input	[63:0] 								lsq_opb_in2,     	// Operand b from Rename  tag or data from prf
	input         								lsq_opb_valid2,   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
	input	[$clog2(`ROB_SIZE):0]				lsq_rob_idx_in2,  	// The rob index of instruction 2
	input	[4:0]								dest_reg_idx2,
	//from mem
	input	[63:0]								mem_data_in,	//when no forwarding possible, load from memory
	input	[63:0]								mem_responce_in,
	input	[4:0]								mem_tag_in,
	
	//retired store idx
	input	[$clog2(`ROB_SIZE):0]				rob_commit_idx1,
	input	[$clog2(`ROB_SIZE):0]				rob_commit_idx2,

	//we need to know weather the instruction commited is a mispredict
	input	thread1_mispredict,
	input	thread2_mispredict,

	output logic [$clog2(`PRF_SIZE)-1:0]		lsq_CDB_dest_tag1,
	output logic [63:0]							lsq_CDB_result_out1,
	output logic 								lsq_CDB_result_is_valid1,

	output logic [$clog2(`PRF_SIZE)-1:0]		lsq_CDB_dest_tag2,
	output logic [63:0]							lsq_CDB_result_out2,
	output logic 								lsq_CDB_result_is_valid2,
	
	output logic	[63:0]						mem_data_out,
	output logic								mem_data_out_valid,
	output logic	[4:0]						mem_store_addr,

	output logic								rob1_excuted,
	output logic								rob2_excuted
);
	
	//LQ
	//the relative ages of two instructions can be determined by examing the physical locations they occupied in LSQ
	//for example, instruction at slot 5 is older than instruction at slot 8
	//lq_reg stores address
	logic	[`LQ_SIZE-1:0]			lq_mem_in1;
	logic	[`LQ_SIZE-1:0]			lq_mem_in2;
	logic	[`LQ_SIZE-1:0]			lq1_clean;
	logic	[`LQ_SIZE-1:0]			lq2_clean;
	logic 	[$clog2(`LQ_SIZE)-1:0]	lq_head1, n_lq_head1, lq_head2, n_lq_head2;
	logic	[$clog2(`LQ_SIZE)-1:0]	lq_tail1, n_lq_tail1, lq_tail2, n_lq_tail2;
	logic	[`LQ_SIZE-1:0]			lq1_is_available;
	logic	[`LQ_SIZE-1:0]			lq2_is_available;
	
	//SQ
	logic	[`LQ_SIZE-1:0]			sq_mem_in1;
	logic	[`LQ_SIZE-1:0]			sq_mem_in2;
	logic	[`SQ_SIZE-1:0]			sq1_clean;
	logic	[`SQ_SIZE-1:0]			sq2_clean;
	logic 	[$clog2(`SQ_SIZE)-1:0]	sq_head1, n_sq_head1, sq_head2, n_sq_head2;
	logic	[$clog2(`SQ_SIZE)-1:0]	sq_tail1, n_sq_tail1, sq_tail2, n_sq_tail2;
	
	//for cdb
	logic	[63:0]		lsq_ra_new1;
	logic	[63:0]		lsq_ra_new2;
	logic	[63:0]		lsq_opb_new1;
	logic	[63:0]		lsq_opb_new2;
	logic				lsq_ra_new_valid1;
	logic				lsq_ra_new_valid2;
	logic				lsq_opb_new_valid1;
	logic				lsq_opb_new_valid2;
	
	logic MEM_INST_TYPE	inst1_type;
	logic MEM_INST_TYPE	inst2_type;
	logic	inst1_is_lq1, inst1_is_lq2,inst1_is_sq1,inst1_is_sq2;
	logic	inst2_is_lq1, inst2_is_lq2,inst2_is_sq1,inst2_is_sq2;
	
	//tag table
	logic	[15:0][$clog2(`SQ_SIZE)+1:0]	tag_table;
	
	assign inst1_type = (inst1_op_type == `LDQ_L_INST)	? IS_LDQ_L_INST	: 
						(inst1_op_type == `LDQ_INST)	? IS_LDQ_INST	: 
						(inst1_op_type == `STQ_C_INST)	? IS_STQ_C_INST	: 
						(inst1_op_type == `STQ_INST)	? IS_STQ_INST	: 
						(inst1_op_type == `LDA_INST) 	? IS_LDA_INST	: 
						NO_INST;
	
	assign inst2_type = (inst2_op_type == `LDQ_L_INST)	? IS_LDQ_L_INST	: 
						(inst2_op_type == `LDQ_INST)	? IS_LDQ_INST	: 
						(inst2_op_type == `STQ_C_INST)	? IS_STQ_C_INST	: 
						(inst2_op_type == `STQ_INST)	? IS_STQ_INST	: 
						(inst2_op_type == `LDA_INST) 	? IS_LDA_INST	: 
						NO_INST;
	
	lq_one_entry [`LQ_SIZE-1:0] lq_t1(
		.clock(clock),
		.reset(reset),
		
		.lq_clean(lq1_clean),
		.lq_free_enable(),
		
		//for instruction1
		.lq_mem_in1(),
		.lq_pc_in1(inst2_pc),
		.lq_inst1_in(inst1_in),
		.lq_opa_in1(lsq_opa_in1),			// Operand a from Rename  data
		.lq_opb_in1(lsq_opb_in1),			// Operand a from Rename  tag or data from prf
		.lq_opb_valid1(lsq_opb_valid1),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		.lq_rob_idx_in1(lsq_rob_idx_in1),  	// The rob index of instruction 1
		.lq_dest_idx1(lsq_dest_idx1),
		.lq_mem_in1(lq_mem_in1),

		//for instruction2
	    .lq_mem_in2(),
		.lq_pc_in2(inst2_pc),
		.lq_inst2_in(inst2_in),
		.lq_opa_in2(lsq_opa_in2),      		// Operand a from Rename  data
		.lq_opb_in2(lsq_opb_in2),     		// Operand b from Rename  tag or data from prf
		.lq_opb_valid2(lsq_opb_valid2),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		.lq_rob_idx_in2(lsq_rob_idx_in2),  	// The rob index of instruction 2
		.lq_dest_idx2(lsq_dest_idx2),
		.lq_mem_in2(lq_mem_in2),    		//ldq
		//cdb
		.lq_cdb1_in(lsq_cdb1_in),     		// CDB bus from functional units 
		.lq_cdb1_tag(lsq_cdb1_tag),    		// CDB tag bus from functional units 
		.lq_cdb1_valid(lsq_cdb1_valid),  	// The data on the CDB is valid 
		.lq_cdb2_in(lsq_cdb2_in),     		// CDB bus from functional units 
		.lq_cdb2_tag(lsq_cdb2_tag),    		// CDB tag bus from functional units 
		.lq_cdb2_valid(lsq_cdb2_valid),  	// The data on the CDB is valid
		//mem
		.lq_mem_data_in(),
		.lq_mem_data_in_valid(),
		//output
		.lq_is_available(lq1_is_available),
		.lq_is_ready(),
		.lq_pc(),
		.lq_inst(),
		.lq_opa(),
		.lq_opb(),
		.lq_addr_valid(),
		.lq_rob_idx(),
		.lq_dest_tag(),
		.lq_mem_value(),
		.lq_mem_value_valid()
	);
	
	lq_one_entry [`LQ_SIZE-1:0] lq_t2(
		.clock(clock),
		.reset(reset),
		
		.lq_clean(lq2_clean),
		.lq_free_enable(),
		
		//for instruction1
		.lq_mem_in1(),
		.lq_pc_in1(inst1_pc),
		.lq_inst1_in(inst1_in),
		.lq_opa_in1(lsq_opa_in1),			// Operand a from Rename  data
		.lq_opb_in1(lsq_opb_in1),			// Operand a from Rename  tag or data from prf
		.lq_opb_valid1(lsq_opb_valid1),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		.lq_rob_idx_in1(lsq_rob_idx_in1),  	// The rob index of instruction 1
		.lq_dest_idx1(lsq_dest_idx1),
		.lq_mem_in1(lq_mem_in1),

		//for instruction2
	    .lq_mem_in2(),
		.lq_pc_in2(inst2_pc),
		.lq_inst2_in(inst2_in),
		.lq_opa_in2(lsq_opa_in2),      		// Operand a from Rename  data
		.lq_opb_in2(lsq_opb_in2),     		// Operand b from Rename  tag or data from prf
		.lq_opb_valid2(lsq_opb_valid2),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		.lq_rob_idx_in2(lsq_rob_idx_in2),  	// The rob index of instruction 2
		.lq_dest_idx2(lsq_dest_idx2),
		.lq_mem_in2(lq_mem_in2),    		//ldq
		//cdb
		.lq_cdb1_in(lsq_cdb1_in),     		// CDB bus from functional units 
		.lq_cdb1_tag(lsq_cdb1_tag),    		// CDB tag bus from functional units 
		.lq_cdb1_valid(lsq_cdb1_valid),  	// The data on the CDB is valid 
		.lq_cdb2_in(lsq_cdb2_in),     		// CDB bus from functional units 
		.lq_cdb2_tag(lsq_cdb2_tag),    		// CDB tag bus from functional units 
		.lq_cdb2_valid(lsq_cdb2_valid),  	// The data on the CDB is valid
		//mem
		.lq_mem_data_in(),
		.lq_mem_data_in_valid(),
		//output
		.lq_is_available(lq2_is_available),
		.lq_is_ready(),
		.lq_pc(),
		.lq_inst(),
		.lq_opa(),
		.lq_opb(),
		.lq_addr_valid(),
		.lq_rob_idx(),
		.lq_dest_tag(),
		.lq_mem_value(),
		.lq_mem_value_valid()
	);
	
	sq_one_entry [`SQ_SIZE-1:0] sq_t1(
		clock(clock),
		reset(reset),
		
		sq_clean(sq1_clean),
	
		//for instruction1
		sq_mem_in1(),
		sq_pc_in1(inst1_pc),
		sq_inst1_in(inst1_in),
		sq_opa_in1(lsq_opa_in1),      	// Operand a from Rename  data
		sq_opb_in1(lsq_opb_in1),      	// Operand a from Rename  tag or data from prf
		sq_opb_valid1(lsq_opa_valid1),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		sq_rob_idx_in1(lsq_rob_idx_in1),  	// The rob index of instruction 1
		sq_dest_idx1(lsq_dest_idx1),

		//for instruction2
		sq_mem_in2(),
		sq_pc_in2(inst2_pc),
		sq_inst2_in(inst2_in),
		sq_opa_in2(lsq_opa_in2),      	// Operand a from Rename  data
		sq_opb_in2(lsq_opb_in2),     	// Operand b from Rename  tag or data from prf
		sq_opb_valid2(lsq_rob_valid2),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		sq_rob_idx_in2(lsq_rob_idx_in2),  	// The rob index of instruction 2
		sq_mem_in2(id_wr_mem_in2),			//stq ********************************************
		sq_dest_idx2(lsq_dest_idx2),
	
		sq_cdb1_in(lsq_cdb1_in),     		// CDB bus from functional units 
		sq_cdb1_tag(lsq_cdb1_tag),    		// CDB tag bus from functional units 
		sq_cdb1_valid(lsq_cdb1_valid),  		// The data on the CDB is valid 
		sq_cdb2_in(lsq_cdb2_in),     		// CDB bus from functional units 
		sq_cdb2_tag(lsq_cdb2_tag),    		// CDB tag bus from functional units 
		sq_cdb2_valid(lsq_cdb2_valid),  		// The data on the CDB is valid

		sq_is_available(),
		sq_is_ready(),
		sq_pc(),
		sq_inst(),
		sq_opa(),
		sq_opb(),
		sq_addr_valid(),
		sq_rob_idx(),
		sq_dest_tag()
	);

	sq_one_entry [`SQ_SIZE-1:0] sq_t2(
		clock(clock),
		reset(reset),
		
		sq_clean(sq2_clean),
	
		//for instruction1
		sq_mem_in1(),
		sq_pc_in1(inst1_pc),
		sq_inst1_in(inst1_in),
		sq_opa_in1(lsq_opa_in1),      	// Operand a from Rename  data
		sq_opb_in1(lsq_opb_in1),      	// Operand a from Rename  tag or data from prf
		sq_opb_valid1(lsq_opa_valid1),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		sq_rob_idx_in1(lsq_rob_idx_in1),  	// The rob index of instruction 1
		sq_dest_idx1(lsq_dest_idx1),

		//for instruction2
		sq_mem_in2(),
		sq_pc_in2(inst2_pc),
		sq_inst2_in(inst2_in),
		sq_opa_in2(lsq_opa_in2),      	// Operand a from Rename  data
		sq_opb_in2(lsq_opb_in2),     	// Operand b from Rename  tag or data from prf
		sq_opb_valid2(lsq_rob_valid2),   	// Is Opb a tag or immediate data (READ THIS COMMENT) 
		sq_rob_idx_in2(lsq_rob_idx_in2),  	// The rob index of instruction 2
		sq_mem_in2(id_wr_mem_in2),			//stq ********************************************
		sq_dest_idx2(lsq_dest_idx2),
	
		sq_cdb1_in(lsq_cdb1_in),     		// CDB bus from functional units 
		sq_cdb1_tag(lsq_cdb1_tag),    		// CDB tag bus from functional units 
		sq_cdb1_valid(lsq_cdb1_valid),  		// The data on the CDB is valid 
		sq_cdb2_in(lsq_cdb2_in),     		// CDB bus from functional units 
		sq_cdb2_tag(lsq_cdb2_tag),    		// CDB tag bus from functional units 
		sq_cdb2_valid(lsq_cdb2_valid),  		// The data on the CDB is valid

		sq_is_available(),
		sq_is_ready(),
		sq_pc(),
		sq_inst(),
		sq_opa(),
		sq_opb(),
		sq_addr_valid(),
		sq_rob_idx(),
		sq_dest_tag()
	);
	
	//read inst
	always_comb begin
		inst1_is_lq1 = 0;
		inst1_is_lq2 = 0;
		inst1_is_sq1 = 0;
		inst1_is sq2 = 0;
		inst2_is_lq1 = 0;
		inst2_is_lq2 = 0;
		inst2_is_sq1 = 0;
		inst2_is_sq2 = 0;
		for (int i = 0; i < `SQ_SIZE; i++) begin
			lq_mem_in1[i] = 0;
			lq_mem_in2[i] = 0;
			sq_mem_in1[i] = 0;
			sq_mem_in2[i] = 0;
		end
		if (lsq_rob_idx_in1[$clog2(`ROB_SIZE)] == 0) begin
			if (inst1_type = IS_LDQ_INST || inst1_type = IS_LDQ_L_INST)
				inst1_is_lq1 = 1;
			else if (inst1_type = IS_STQ_INST || inst1_type = IS_STQ_C_INST)
				inst1_is_sq1 = 1;
			end
		end
		else begin
			if (inst1_type = IS_LDQ_INST || inst1_type = IS_LDQ_L_INST)
				inst1_is_lq2 = 1;
			else if (inst1_type = IS_STQ_INST || inst1_type = IS_STQ_C_INST)
				inst1_is_sq2 = 1;
			end
		end
		
		if (lsq_rob_idx_in2[$clog2(`ROB_SIZE)] == 0) begin
			if (inst2_type = IS_LDQ_INST || inst2_type = IS_LDQ_L_INST)
				inst2_is_lq1 = 1;
			else if (inst2_type = IS_STQ_INST || inst2_type = IS_STQ_C_INST)
				inst2_is_sq1 = 1;
			end
		end
		else begin
			if (inst2_type = IS_LDQ_INST || inst2_type = IS_LDQ_L_INST)
				inst2_is_lq2 = 1;
			else if (inst2_type = IS_STQ_INST || inst2_type = IS_STQ_C_INST)
				inst2_is_sq2 = 1;
			end
		end
		n_lq_tail1 = lq_tail1 + inst1_is_lq1 + inst2_is_lq1;
		n_lq_tail2 = lq_tail2 + inst1_is_lq2 + inst2_is_lq2;
		n_sq_tail1 = sq_tail1 + inst1_is_sq1 + inst2_is_sq1;
		n_sq_tail2 = sq_tail2 + inst1_is_sq2 + inst2_is_sq2;
		for (int j = 0; j < inst1_is_lq1 + inst2_is_lq1; j++)
			lq_mem_in1[lq_tail1+j] = 1;
		for (int k = 0; k < inst1_is_lq2 + inst2_is_lq2; k++)
			lq_mem_in2[lq_tail2+k] = 1;
		for (int l = 0; l < inst1_is_sq1 + inst2_is_sq1; l++)
			sq_mem_in1[sq_tail1+l] = 1;
		for (int m = 0; m < inst1_is_sq2 + inst2_is_sq2; m++)
			sq_mem_in2[sq_tail2+m] = 1;
	end
	
	//output inst
	always_comb begin
		
	end
	
	//tag table
	always_comb begin
	end
	
	//head and tail move
	always_ff @ (posedge clock) begin
		if(reset) begin
			sq_head1 			<= #1 0;
			sq_tail1 			<= #1 0;
			sq_head2 			<= #1 0;
			sq_tail2 			<= #1 0;
			lq_head1 			<= #1 0;
			lq_tail1 			<= #1 0;
			lq_head2			<= #1 0;
			lq_tail2			<= #1 0;
		end
		else begin
			sq_head1 			<= #1 n_sq_head1;
			sq_tail1 			<= #1 n_sq_tail1;
			sq_head2 			<= #1 n_sq_head2;
			sq_tail2 			<= #1 n_sq_tail2;
			lq_head1 			<= #1 n_lq_head1;
			lq_tail1 			<= #1 n_lq_tail1;
			lq_head2			<= #1 n_lq_head2;
			lq_tail2			<= #1 n_lq_tail2;
		end
	end
	
	//mispredict
	always_comb begin
		n_sq_tail1	= 0;
		n_sq_tail2	= 0;
		lq1_clean	= 0;
		lq2_clean	= 0;
		sq1_clean	= 0;
		sq2_clean	= 0;
		if (thread1_mispredict) begin
			n_sq_tail1 = sq_head1;
			n_lq_tail1 = lq_head1;
			for (int i = 0; i < `SQ_SIZE; i++) begin
				lq1_clean[i] = 1;
				sq1_clean[i] = 1;
			end
		end
		if (thread2_mispredict) begin
			n_sq_tail2 = sq_head2;
			n_lq_tail2 = lq_head2;
			for (int i = 0; i < `SQ_SIZE; i++) begin
				lq2_clean[i] = 1;
				sq2_clean[i] = 1;
			end
		end
	end
	
endmodule
