/////////////////////////////////////////////////////////////////////////
//                                                                     //
//                                                                     //
//   Modulename :  testbench.v                                         //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline;       //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`timescale 1ns/100ps

`include "sys_defs.vh"

module testbench;

	//variables used in the testbench
    	logic         clock;                    // System clock
    	logic         reset;                    // System reset
	logic [31:0]  clock_count;
	logic [31:0]  instr_count;
    	int           wb_fileno;
	
    	logic [3:0]   mem2proc_response;        // Tag from memory about current request
    	logic [63:0]  mem2proc_data;            // Data coming back from memory
    	logic [3:0]   mem2proc_tag;              // Tag from memory about current reply

    	logic [1:0]   proc2mem_command;    // command sent to memory
    	logic [63:0]  proc2mem_addr;      // Address sent to memory
   	logic [63:0]  proc2mem_data;      // Data sent to memory

    	logic [3:0]   pipeline_completed_insts;
    	logic [3:0]   pipeline_error_status;

    	// testing hooks (these must be exported so we can test
    	// the synthesized version) data is tested by looking at
    	// the final values in memory

    	//output
    	// Outputs from IF-Stage 
    	//Output from rob
    	logic							ROB_commit1_valid;
    	logic [63:0]					PRF_writeback_value1;
    	logic [63:0]					ROB_commit1_pc;
    	logic [$clog2(`ARF_SIZE)-1:0]	ROB_commit1_arn_dest;
    	logic							ROB_commit1_wr_en;
    	logic							ROB_commit2_valid;
    	logic [63:0]					PRF_writeback_value2;
    	logic [63:0]					ROB_commit2_pc;
   	logic [$clog2(`ARF_SIZE)-1:0]	ROB_commit2_arn_dest;
    	logic							ROB_commit2_wr_en;

	processor processor_0(
		//input
    		.clock(clock),                    // System clock
    		.reset(reset),                    // System reset
    		.mem2proc_response(mem2proc_response),        // Tag from memory about current request
    		.mem2proc_data(mem2proc_data),            // Data coming back from memory
    		.mem2proc_tag(mem2proc_tag),              // Tag from memory about current reply

		//output
    		.proc2mem_command(proc2mem_command),    // command sent to memory
    		.proc2mem_addr(proc2mem_addr),      // Address sent to memory
    		.proc2mem_data(proc2mem_data),      // Data sent to memory

    		.pipeline_completed_insts(pipeline_completed_insts),
    
    		.pipeline_error_status(pipeline_error_status),
    		//.pipeline_commit_wr_idx(pipeline_commit_wr_idx),
    		//.pipeline_commit_wr_data(pipeline_commit_wr_data),
    		//.pipeline_commit_wr_en(pipeline_commit_wr_en),
    		//.pipeline_commit_NPC(pipeline_commit_NPC),


    		// testing hooks (these must be exported so we can test
    		// the synthesized version) data is tested by looking at
    		// the final values in memory

    		//output
    		//Output from rob
    		.ROB_commit1_valid(ROB_commit1_valid),
    		.ROB_commit1_pc(ROB_commit1_pc),
    		.ROB_commit1_arn_dest(ROB_commit1_arn_dest),
    		.ROB_commit1_wr_en(ROB_commit1_wr_en),
    		.PRF_writeback_value1(PRF_writeback_value1),
    		.ROB_commit2_valid(ROB_commit2_valid),
    		.ROB_commit2_pc(ROB_commit2_pc),
    		.ROB_commit2_arn_dest(ROB_commit2_arn_dest),
    		.ROB_commit1_wr_en(ROB_commit1_wr_en),
    		.PRF_writeback_value2(PRF_writeback_value2)		
	);

// Instantiate the Data Memory
	mem memory (// Inputs
			.clk               (clock),
			.proc2mem_command  (proc2mem_command),
			.proc2mem_addr     (proc2mem_addr),
			.proc2mem_data     (proc2mem_data),

			 // Outputs

			.mem2proc_response (mem2proc_response),
			.mem2proc_data     (mem2proc_data),
			.mem2proc_tag      (mem2proc_tag)
		   );

	// Generate System Clock
	always
	begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clock = ~clock;
	end

	// Task to display # of elapsed clock edges
	task show_clk_count;
		real cpi;

		begin
			cpi = (clock_count + 1.0) / instr_count;
			$display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
			clock_count+1, instr_count, cpi);
			$display("@@  %4.2f ns total time to execute\n@@\n",
			clock_count*`VIRTUAL_CLOCK_PERIOD);
		end
		
	endtask  // task show_clk_count 

  // Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;
		int showing_data;
		begin
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1)
				if (memory.unified_memory[k] != 0)
				begin
					$display("@@@ mem[%5d] = %x : %0d", k*8,	memory.unified_memory[k], 
																memory.unified_memory[k]);
					showing_data=1;
				end
				else if(showing_data!=0)
				begin
					$display("@@@");
					showing_data=0;
				end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal

  	initial begin
  		`ifdef DUMP
			  $vcdplusdeltacycleon;
			  $vcdpluson();
			  $vcdplusmemon(memory.unified_memory);
		`endif
    		clock = 1'b0;
    		reset = 1'b0;
	
		//#10
   		// Pulse the reset signal
		$display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
   		reset = 1'b1;
    		@(posedge clock);
    		@(posedge clock);
		
		$readmemh("program.mem", memory.unified_memory);
	
		@(posedge clock);
    		@(posedge clock);
    		`SD;
    		// This reset is at an odd time to avoid the pos & neg clock edges
	
    		reset = 1'b0;
		$display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);
	
    		wb_fileno = $fopen("writeback_t1.out");
    	
    		//Open header AFTER throwing the reset otherwise the reset state is displayed

  	end


  // Count the number of posedges and number of instructions completed
  // till simulation ends
	
	// Count the number of posedges and number of instructions completed
	// till simulation ends
	always @(posedge clock or posedge reset)
	begin
		if(reset)
		begin
			clock_count <= `SD 0;
			instr_count <= `SD 0;
		end
		else
		begin
			clock_count <= `SD (clock_count + 1);
			instr_count <= `SD (instr_count + pipeline_completed_insts);
		end
	end  

  	always @(negedge clock) begin
		if(reset)
			$display(	"@@\n@@  %t : System STILL at reset, can't show anything\n@@",
						$realtime);
		else
		begin
		  `SD;
		  `SD;

       	// print the writeback information to writeback.out
	//for writeback.out we need pipeline_completed_insts pipeline_commit_wr_en
	//pipeline_commit_NPC  pipeline_commit_wr_idx pipeline_commit_wr_data
       			if(pipeline_completed_insts>0) begin
         			if(ROB_commit1_wr_en)
           				$fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
                     				ROB_commit1_pc,
                     				ROB_commit1_arn_dest,
                     				PRF_writeback_value1);
        			else
          				$fdisplay(wb_fileno, "PC=%x, ---",ROB_commit1_pc);
				if(ROB_commit2_wr_en)
           				$fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
                     				ROB_commit2_pc,
                     				ROB_commit2_arn_dest,
                     				PRF_writeback_value2);
        			else
        				$fdisplay(wb_fileno, "PC=%x, ---",ROB_commit2_pc);
      			end

      // deal with any halting conditions
      /*if(pipeline_error_status != NO_ERROR) begin
        print_close(); // close the pipe_print output file
        $fclose(wb_fileno);
        #100 $finish;
      end*/
			// deal with any halting conditions
			if(pipeline_error_status!=NO_ERROR)
			begin
				$display(	"@@@ Unified Memory contents hex on left, decimal on right: ");
							show_mem_with_decimal(0,`MEM_64BIT_LINES - 1); 
				// 8Bytes per line, 16kB total

				$display("@@  %t : System halted\n@@", $realtime);

				case(pipeline_error_status)
					HALTED_ON_MEMORY_ERROR:  
						$display(	"@@@ System halted on memory error");
					HALTED_ON_HALT_I1:          
						$display(	"@@@ System halted on HALT_I1 instruction");
					HALTED_ON_HALT_I2:          
						$display(	"@@@ System halted on HALT_I2 instruction");
					HALTED_ON_ILLEGAL_I1:
						$display(	"@@@ System halted on illegal_I1 instruction");
					HALTED_ON_ILLEGAL_I2:
						$display(	"@@@ System halted on illegal_I2 instruction");
					default: 
						$display(	"@@@ System halted on unknown error code %x",
									pipeline_error_status);
				endcase
				$display("@@@\n@@");
				show_clk_count;
				//print_close(); // close the pipe_print output file
				$fclose(wb_fileno);
				#100 $finish;
			end
		end// if(reset) 
    	end  

endmodule  // module testbench


