//////////////////////////////////////////////////////////////////////////
//                                                                      //
//   Modulename :  prf.v                                       	        //
//                                                                      //
//   Description :                                                      //
//                                                                      //
//                                                                      // 
//                                                                      //
//                                                                      // 
//                                                                      //
//                                                                      //
//////////////////////////////////////////////////////////////////////////

module prf(
	input					clock,
	input					reset,

	input					cdb1_valid,
	input	[$clog2(`PRF_SIZE)-1:0]		cdb1_tag,
	input   [63:0]				cdb1_out,
	input					cdb2_valid,
	input	[$clog2(`PRF_SIZE)-1:0]		cdb2_tag,
	input   [63:0]				cdb2_out,

	input	[$clog2(`PRF_SIZE)-1:0]		inst1_opa_prf_idx,			//opa prf index of instruction1
	input	[$clog2(`PRF_SIZE)-1:0]		inst1_opb_prf_idx,			//opb prf index of instruction1
	input	[$clog2(`PRF_SIZE)-1:0]		inst2_opa_prf_idx,			//opa prf index of instruction2
	input	[$clog2(`PRF_SIZE)-1:0]		inst2_opb_prf_idx,			//opb prf index of instruction2

	input					rat1_allocate_new_prf,			//the request from rat1 for allocating a new prf entry
	input					rat2_allocate_new_prf,			//the request from rat2 for allocating a new prf entry

	input	[`PRF_SIZE-1:0]			rrat1_prf_free_list,			//when a branch is mispredict, RRAT1 gives a freelist to PRF
	input	[`PRF_SIZE-1:0]			rrat2_prf_free_list,			//when a branch is mispredict, RRAT2 gives a freelist to PRF
	input	[`PRF_SIZE-1:0]			rat1_prf_free_list,			//when a branch is mispredict, RAT1 gives a freelist to PRF
	input	[`PRF_SIZE-1:0]			rat2_prf_free_list,			//when a branch is mispredict, RAT2 gives a freelist to PRF
	input					rrat1_branch_mistaken_free_valid,	//when a branch is mispredict, RRAT1 gives out a signal enable PRF to free its register files
	input					rrat2_branch_mistaken_free_valid,	//when a branch is mispredict, RRAT2 gives out a signal enable PRF to free its register files

	input					rrat1_prf_free_valid,			//when an instruction retires from RRAT1, RRAT1 gives out a signal enable PRF to free its register. 
	input					rrat2_prf_free_valid,			//when an instruction retires from RRAT2, RRAT1 gives out a signal enable PRF to free its register.
	input	[$clog2(`PRF_SIZE)-1:0] 	rrat1_prf_free_idx,			//when an instruction retires from RRAT1, RRAT1 will free a PRF, and this is its index. 
	input	[$clog2(`PRF_SIZE)-1:0] 	rrat2_prf_free_idx,			//when an instruction retires from RRAT2, RRAT2 will free a PRF, and this is its index.

	output	logic				rat1_prf_rename_valid_out,		//when RAT1 asks the PRF to allocate a new entry, PRF should make sure the returned index is valid.
	output	logic				rat2_prf_rename_valid_out,		//when RAT2 asks the PRF to allocate a new entry, PRF should make sure the returned index is valid.
	output	logic	[$clog2(`PRF_SIZE)-1:0]	rat1_prf_rename_idx_out,		//when RAT1 asks the PRF to allocate a new entry, PRF should return the index of this newly allocated entry.
	output	logic	[$clog2(`PRF_SIZE)-1:0]	rat2_prf_rename_idx_out,		//when RAT2 asks the PRF to allocate a new entry, PRF should return the index of this newly allocated entry.

	output  logic	[63:0]			inst1_opa_prf_value,			//opa prf value of instruction1
	output	logic	[63:0]			inst1_opb_prf_value,			//opb prf value of instruction1
	output  logic	[63:0]			inst2_opa_prf_value,			//opa prf value of instruction2
	output	logic	[63:0]			inst2_opb_prf_value,			//opb prf value of instruction2

	output  logic				inst1_opa_valid,			//whether opa load from prf of instruction1 is valid
	output	logic				inst1_opb_valid,			//whether opb load from prf of instruction1 is valid
	output  logic				inst2_opa_valid,			//whether opa load from prf of instruction2 is valid
	output	logic				inst2_opb_valid				//whether opa load from prf of instruction2 is valid

);
	//internal signal for input
	logic	[`PRF_SIZE-1:0]			internal_free_this_entry;
	logic   [`PRF_SIZE-1:0][63:0]		internal_data_in;
	logic	[`PRF_SIZE-1:0]			internal_write_prf_enable;
	logic	[`PRF_SIZE-1:0]			internal_assign_a_free_reg1;
	logic	[`PRF_SIZE-1:0]			internal_assign_a_free_reg2;

	//internal signal for output	
	logic   [`PRF_SIZE-1:0]			internal_prf_available;
	logic   [`PRF_SIZE-1:0]			internal_prf_ready;
	logic   [`PRF_SIZE-1:0][63:0]		internal_data_out;

	//other registers to store value



	prf_one_entry prf1[`PRF_SIZE-1:0](
		//input
		.clock(clock),
		.reset(reset),
		.free_this_entry(free_this_entry),
    		.data_in(internal_data_in),
		.write_prf_enable(internal_write_prf_enable),
		.assign_a_free_reg(internal_assign_a_free_reg1),

		//output
		.prf_available(internal_prf_available),
		.prf_ready(internal_prf_ready),
		.data_out(internal_data_out)
		    );

	//this priority selector choose a register from free lists for RAT1
	//and return the index of this newly allocated register
	priority_selector #(.SIZE(`PRF_SIZE)) prf_psl1( 
		.req(internal_prf_available),
	        .en(rat1_allocate_new_prf),
        	.gnt(internal_assign_a_free_reg1)
	);

	


	always_comb
	begin
		for(int i=0;i<`PRF_SIZE;i++)
		begin
			if (internal_assign_a_free_reg1[i]==1'b1)
			begin
				rat1_prf_rename_valid_out = 1'b1;
				rat1_prf_rename_idx_out   = i;
				break;
			end
			else
			begin
				rat1_prf_rename_valid_out = 1'b0;
				rat1_prf_rename_idx_out   = 0;
			end
		end
	end

	//this priority selector choose a second register from free lists for RAT2
	//and return the index of this newly allocated register

	priority_selector #(.SIZE(`PRF_SIZE)) prf_psl2( 
		.req((~internal_assign_a_free_reg1)&internal_prf_available),
	        .en(rat2_allocate_new_prf),
        	.gnt(internal_assign_a_free_reg2)
	);

	always_comb
	begin
		for(int i=0;i<`PRF_SIZE;i++)
		begin
			if (internal_assign_a_free_reg2[i]==1'b1)
			begin
				rat2_prf_rename_valid_out = 1'b1;
				rat2_prf_rename_idx_out   = i;
				break;
			end
			else
			begin
				rat2_prf_rename_valid_out = 1'b0;
				rat2_prf_rename_idx_out   = 0;
			end
		end
	end

	//store the data from CDB
	always_comb
	begin
		for(int i=0;i<`PRF_SIZE;i++)
		begin
			if      ((cdb1_tag == i) && (cdb1_valid) && 
				 (!internal_prf_available[i]) && 
				 (!internal_prf_ready))
			begin
				internal_data_in[i] 	     = cdb1_out;
				internal_write_prf_enable[i] = 1'b1;
			end
			else if ((cdb2_tag == i) && (cdb2_valid) && 
				 (!internal_prf_available[i]) && 
				 (!internal_prf_ready))
			begin
				internal_data_in[i] 	     = cdb2_out;
				internal_write_prf_enable[i] = 1'b1;
			end
			else
			begin
				internal_data_in[i] 	     = 0;
				internal_write_prf_enable[i] = 1'b0;
			end
		end
	end

	//load data to the opa and opb of RS
	always_comb
	begin
		for(int i=0;i<`PRF_SIZE;i++)
		begin
			if ((inst1_opa_prf_idx==i) && internal_prf_ready[i] && (!internal_prf_available))
			begin
				inst1_opa_prf_value = internal_data_out[i];
				inst1_opa_valid	    = 1'b1;
			end
			else
			begin
				inst1_opa_prf_value = 0;
				inst1_opa_valid	    = 1'b0;
			end

			if ((inst1_opb_prf_idx==i) && internal_prf_ready[i] && (!internal_prf_available))
			begin
				inst1_opb_prf_value = internal_data_out[i];
				inst1_opb_valid	    = 1'b1;
			end
			else
			begin
				inst1_opb_prf_value = 0;
				inst1_opb_valid	    = 1'b0;
			end
			
			if ((inst2_opa_prf_idx==i) && internal_prf_ready[i] && (!internal_prf_available))
			begin
				inst2_opa_prf_value = internal_data_out[i];
				inst2_opa_valid	    = 1'b1;
			end
			else
			begin
				inst2_opa_prf_value = 0;
				inst2_opa_valid	    = 1'b0;
			end

			if ((inst2_opb_prf_idx==i) && internal_prf_ready[i] && (!internal_prf_available))
			begin
				inst2_opb_prf_value = internal_data_out[i];
				inst2_opb_valid	    = 1'b1;
			end
			else
			begin
				inst2_opb_prf_value = 0;
				inst2_opb_valid	    = 1'b0;
			end
		end
	end


	//free prf
	always_comb
	begin
	
		//free one entry of PRF 
		//this happens when RoB retires an intruction
		//RRAT will give out the physical register index to tell which entry of PRF should be free
		for(int i=0;i<`PRF_SIZE;i++)
		begin
			if 	((rrat1_prf_free_idx==i)&&(rrat1_prf_free_valid))
			begin
				internal_free_this_entry[i] = 1'b1;
			end
			else if ((rrat2_prf_free_idx==i)&&(rrat2_prf_free_valid))
			begin
				internal_free_this_entry[i] = 1'b1;
			end
			else
			begin
				internal_free_this_entry[i] = 1'b0;
			end
		end

		//when there is a branch mispredict, 
		//we need to free all the registers that are not in the RRAT
		//because we have two RRAT updating the PRF, 
		//when RRAT1 frees the registers, we must check RAT2
		//when RRAT2 frees the registers, we must check RAT1
		if (rrat1_branch_mistaken_free_valid)
		begin
			for(int i=0;i<`PRF_SIZE;i++)
			begin
				if(rrat1_prf_free_list[i]&&rat2_prf_free_list[i])
				begin
					internal_free_this_entry[i] = 1'b1;
				end
				else
				begin
					internal_free_this_entry[i] = 1'b0;
				end
			end
		end
		else if (rrat2_branch_mistaken_free_valid)
		begin
			for(int i=0;i<`PRF_SIZE;i++)
			begin
				if(rrat2_prf_free_list[i]&&rat1_prf_free_list[i])
				begin
					internal_free_this_entry[i] = 1'b1;
				end
				else
				begin
					internal_free_this_entry[i] = 1'b0;
				end
			end
		end
		else
		begin
			internal_free_this_entry = 0;
		end		
	end
endmodule
