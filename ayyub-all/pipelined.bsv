import FIFO::*;
import SpecialFIFOs::*;
import RegFile::*;
import RVUtil::*;
import Vector::*;
import KonataHelper::*;
import Printf::*;
import Ehr::*;

typedef struct { Bit#(4) byte_en; Bit#(32) addr; Bit#(32) data; } Mem deriving (Eq, FShow, Bits);

interface RVIfc;
    method ActionValue#(Mem) getIReq();
    method Action getIResp(Mem a);
    method ActionValue#(Mem) getDReq();
    method Action getDResp(Mem a);
    method ActionValue#(Mem) getMMIOReq();
    method Action getMMIOResp(Mem a);
endinterface
typedef struct { Bool isUnsigned; Bit#(2) size; Bit#(2) offset; Bool mmio; } MemBusiness deriving (Eq, FShow, Bits);

function Bool isMMIO(Bit#(32) addr);
    Bool x = case (addr) 
        32'hf000fff0: True;
        32'hf000fff4: True;
        32'hf000fff8: True;
        default: False;
    endcase;
    return x;
endfunction

typedef struct { Bit#(32) pc;
                 Bit#(32) ppc;
                 Bit#(3) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dInst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(3) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    Bit#(32) pc;

    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dInst;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

(* synthesize *)
module mkpipelined(RVIfc);
    Bool debug = True;
    
    // Interface with memory and devices
    FIFO#(Mem) toImem <- mkBypassFIFO;
    FIFO#(Mem) fromImem <- mkBypassFIFO;
    FIFO#(Mem) toDmem <- mkBypassFIFO;
    FIFO#(Mem) fromDmem <- mkBypassFIFO;
    FIFO#(Mem) toMMIO <- mkBypassFIFO;
    FIFO#(Mem) fromMMIO <- mkBypassFIFO;

    FIFO#(F2D) f2d <- mkFIFO;
    FIFO#(D2E) d2e <- mkFIFO;
    FIFO#(E2W) e2w <- mkFIFO;

    Ehr#(5, Bit#(32)) pc <- mkEhr(32'h0000000);
    Ehr#(5, Bit#(3)) epoch <- mkEhr(0);

    Vector#(32, Ehr#(5, Bit#(32))) rf <- replicateM(mkEhr(0));
    Vector#(32, Ehr#(5, Bit#(4))) scoreboard <- replicateM(mkEhr(0));

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);

	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;

    
    Reg#(Bool) starting <- mkReg(True);
	rule do_tic_logging;
        if (starting) begin
            let f <- $fopen(dumpFile, "w") ;
            lfh <= f;
            $fwrite(f, "Kanata\t0004\nC=\t1\n");
            starting <= False;
        end
		konataTic(lfh);
	endrule


    Reg#(Bit#(32)) cycle <- mkReg(0);
    rule incr;
        cycle <= cycle + 1;
    endrule

		
    rule fetch if (!starting);
        // if (!stall[1]) begin
            // if(debug) $display("Cycle: %d | %x | Fetch", cycle, pc[1]);
            
            // Bit#(32) pc_fetched = pc;
            // You should put the pc that you fetch in pc_fetched
            // Below is the code to support Konata's visualization
            let iid <- fetch1Konata(lfh, fresh_id, 0);
            labelKonataLeft(lfh, iid, $format("PC %x", pc[1]));
            // TODO implement fetch
            




            
            // current_id <= iid;
            let req = Mem {
                byte_en : 0,
                addr : pc[1],
                data : 0
            };

            toImem.enq(req);

            F2D fetchInfo = F2D {
                pc: pc[1],
                ppc: pc[1] + 4,
                epoch: epoch[1],
                k_id: iid
            };

            f2d.enq( fetchInfo );
            
            pc[1] <= pc[1] + 4;
        // end
        


        // This will likely end with something like:
        // f2d.enq(F2D{ ..... k_id: iid});
        // iid is the unique identifier used by konata, that we will pass around everywhere for each instruction
    endrule

    rule decode if (!starting);
        // TODO

        F2D fetchInfo = f2d.first();

        let resp = fromImem.first();
        let instr = resp.data;
        let decodedInst = decodeInst(instr);

		
		// dInst <= decodedInst;

		if (debug) $display("Cycle: %d | %x | [Decode] ", cycle, fetchInfo.pc, fshow(decodedInst));

        let rs1_idx = getInstFields(instr).rs1;
        let rs2_idx = getInstFields(instr).rs2;
        let rd_idx = getInstFields(instr).rd;

        let should_stall_rs1 = scoreboard[rs1_idx][2] != 0;
        let should_stall_rs2 = scoreboard[rs2_idx][2] != 0;
        let should_stall = should_stall_rs1 || should_stall_rs2;
        if (!should_stall) begin
        
		let rv1 = (rs1_idx == 0 ? 0 : rf[rs1_idx][1]);
		let rv2 = (rs2_idx == 0 ? 0 : rf[rs2_idx][1]);
            if (decodedInst.valid_rd && (rd_idx != 0)) begin
                scoreboard[rd_idx][2] <= scoreboard[rd_idx][2] + 1;
            end
            

            decodeKonata(lfh, fetchInfo.k_id);
            labelKonataLeft(lfh, fetchInfo.k_id, $format("Instr bits: %x", decodedInst.inst));
            labelKonataLeft(lfh, fetchInfo.k_id, $format(" Potential r1: %x, Potential r2: %x" , rv1, rv2));

            // rv1 <= rs1;
            // rv2 <= rs2;
            // state <= Execute;

            D2E decodeInfo = D2E {
                dInst: decodedInst,
                pc: fetchInfo.pc,
                ppc: fetchInfo.ppc,
                epoch: fetchInfo.epoch,
                rv1: rv1,
                rv2: rv2,
                k_id: fetchInfo.k_id
            };

            fromImem.deq();
            f2d.deq();
            d2e.enq( decodeInfo );

            // pc <= newPc[1];
        
        // end

            // stall[0] <= False;

        end
        else begin
            // stall[0] <= True;
        end


        // To add a decode event in Konata you will likely do something like:
        //  let from_fetch = f2d.first();
   	    //	decodeKonata(lfh, from_fetch.k_id);
        //  labelKonataLeft(lfh,from_fetch.k_id, $format("Any information you would like to put in the left pane in Konata, attached to the current instruction"));
    endrule

    rule execute if (!starting);
        // TODO

        D2E decodeInfo = d2e.first();
        d2e.deq();

        let dInst = decodeInfo.dInst;
        // let pc = decodeInfo.pc;
        let rv1 = decodeInfo.rv1;
        let rv2 = decodeInfo.rv2;
        // let dInst = decodeInfo.dInst;

        let current_id = decodeInfo.k_id;

        if (decodeInfo.epoch == epoch[0]) begin

            if (debug) $display("Cycle: %d | %x | [Execute] ", cycle, decodeInfo.pc, fshow(dInst));
            executeKonata(lfh, current_id);

            let imm = getImmediate(dInst);
            Bool mmio = False;
            let data = execALU32(dInst.inst, rv1, rv2, imm, decodeInfo.pc);
            let isUnsigned = 0;
            let funct3 = getInstFields(dInst.inst).funct3;
            let size = funct3[1:0];
            let addr = rv1 + imm;
            Bit#(2) offset = addr[1:0];
            if (isMemoryInst(dInst)) begin
                // Technical details for load byte/halfword/word
                let shift_amount = {offset, 3'b0};
                let byte_en = 0;
                case (size) matches
                2'b00: byte_en = 4'b0001 << offset;
                2'b01: byte_en = 4'b0011 << offset;
                2'b10: byte_en = 4'b1111 << offset;
                endcase
                data = rv2 << shift_amount;
                addr = {addr[31:2], 2'b0};
                isUnsigned = funct3[2];
                let type_mem = (dInst.inst[5] == 1) ? 15 : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                if (isMMIO(addr)) begin 
                    if (debug) $display("Cycle: %d | %x | [Execute] MMIO", cycle, decodeInfo.pc, fshow(req));
                    toMMIO.enq(req);
                    labelKonataLeft(lfh,current_id, $format(" MMIO ", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh,current_id, $format(" MEM ", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    labelKonataLeft(lfh,current_id, $format(" Ctrl instr "));
                    data = decodeInfo.pc + 4;
            end else begin 
                labelKonataLeft(lfh,current_id, $format(" Standard instr "));
            end
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, decodeInfo.pc);
            let nextPc = controlResult.nextPC;

            // $display("%x | %x | %x", pc, decodeInfo.ppc, nextPc);

            if (decodeInfo.ppc != nextPc) begin
                // $display("%x", decodeInfo.pc);

                // $display("Switching epoch | %x | %x | %x", decodeInfo.pc, decodeInfo.ppc, nextPc);

                epoch[0] <= epoch[0] + 1;
                pc[0] <= nextPc;

                // e[0] <= True;
                

                // $display("%x", nextPc);
                
            end
            // else begin
            //     e[0] <= False;
            // end

            

            // else begin
            //     pc <= pc + 4;
            // end

            // newPc[0] <= nextPc;



            // pc <= nextPc;
            // rvd <= data;

            labelKonataLeft(lfh,current_id, $format(" ALU output: %x" , data));

            // mem_business <= MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio};
            // state <= Writeback;


            let business = MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio};
            E2W executeInfo = E2W {
                pc: decodeInfo.pc,
            
                mem_business: business,
                data: data,
                dInst: dInst,
                k_id: current_id
            };

            e2w.enq( executeInfo );

            // pc <= nextPc;
        end
        else begin
            squashed.enq(current_id);
        
            // if (debug) $display("Cycle: %d | No execute", cycle);
            // if (debug) $display("Dropping %x | %d | %d", pc, epoch, decodeInfo.epoch);
            
            if (decodeInfo.dInst.valid_rd) begin
                let rd_idx = getInstFields(decodeInfo.dInst.inst).rd;
                if (rd_idx != 0) begin
                    // rf[rd_idx] <= data;
                    scoreboard[rd_idx][1] <= scoreboard[rd_idx][1] - 1;
                end
            end
        end

        



        // Similarly, to register an execute event for an instruction:
    	//	executeKonata(lfh, k_id);
    	// where k_id is the unique konata identifier that has been passed around that came from the fetch stage


    	// Execute is also the place where we advise you to kill mispredicted instructions
    	// (instead of Decode + Execute like in the class)
    	// When you kill (or squash) an instruction, you should register an event for Konata:
    	
        // squashed.enq(current_inst.k_id);

        // This will allow Konata to display those instructions in grey
    endrule

    rule writeback if (!starting);
        // TODO

        E2W executeInfo = e2w.first();
        e2w.deq();

        writebackKonata(lfh, executeInfo.k_id);
        retired.enq(executeInfo.k_id);


		// state <= Fetch;

        let mem_business = executeInfo.mem_business;
        let data = executeInfo.data;
        let dInst = executeInfo.dInst;
        

        let fields = getInstFields(dInst.inst);
        if (isMemoryInst(dInst)) begin // (* // write_val *)
            let resp = ?;
		    if (mem_business.mmio) begin 
                resp = fromMMIO.first();
		        fromMMIO.deq();
		    end else begin 
                resp = fromDmem.first();
		        fromDmem.deq();
		    end
            let mem_data = resp.data;
            mem_data = mem_data >> {mem_business.offset ,3'b0};
            case ({pack(mem_business.isUnsigned), mem_business.size}) matches
	     	3'b000 : data = signExtend(mem_data[7:0]);
	     	3'b001 : data = signExtend(mem_data[15:0]);
	     	3'b100 : data = zeroExtend(mem_data[7:0]);
	     	3'b101 : data = zeroExtend(mem_data[15:0]);
	     	3'b010 : data = mem_data;
             endcase
		end
		// if(debug) $display("Cycle: %d | %x | [Writeback]", cycle, executeInfo.pc, fshow(dInst));
        if (!dInst.legal) begin
			// $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
			// $display("Illegal instruction detected");
            // $display("%x", executeInfo.pc);
            $finish(0);	// Fault
	    end
		if (dInst.valid_rd) begin
            let rd_idx = fields.rd;
            if (rd_idx != 0) begin
                rf[rd_idx][0] <= data;
                scoreboard[rd_idx][0] <= scoreboard[rd_idx][0] - 1;
            end
		end







        // Similarly, to register an execute event for an instruction:
	   	//	writebackKonata(lfh,k_id);


	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	   	// Konata requires us to register the event as well using the following: 
		// retired.enq(k_id);
	endrule
		

    // rule t;
    //     $display("%x", pc);
    //     for (Integer i = 0; i < 32; i = i + 1) begin
    //         $display("Score ", i, scoreboard[i][3] );
    //     end
    // endrule

	// ADMINISTRATION:

    rule administrative_konata_commit;
		    retired.deq();
		    let f = retired.first();
		    commitKonata(lfh, f, commit_id);
	endrule
		
	rule administrative_konata_flush;
		    squashed.deq();
		    let f = squashed.first();
		    squashKonata(lfh, f);
	endrule
		
    method ActionValue#(Mem) getIReq();
		toImem.deq();
		return toImem.first();
    endmethod
    method Action getIResp(Mem a);
    	fromImem.enq(a);
    endmethod
    method ActionValue#(Mem) getDReq();
		toDmem.deq();
		return toDmem.first();
    endmethod
    method Action getDResp(Mem a);
		fromDmem.enq(a);
    endmethod
    method ActionValue#(Mem) getMMIOReq();
		toMMIO.deq();
		return toMMIO.first();
    endmethod
    method Action getMMIOResp(Mem a);
		fromMMIO.enq(a);
    endmethod
endmodule
