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

interface Scoreboardinterface;
    method ActionValue#(Bool) search1(Bit#(5) index);
    method ActionValue#(Bool) search2(Bit#(5) index);
    method Action insert(Bit#(5) index);
    method Action remove1(Bit#(5) index);
    method Action remove2(Bit#(5) index);
endinterface
interface BypassRegInt;
    method ActionValue#(Bit#(32)) read1(Bit#(5) index );
    method ActionValue#(Bit#(32)) read2(Bit#(5) index);
    method Action write(Bit#(5) index , Bit#(32) value);
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
                 Bit#(1) epoch; 
                 KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
             } F2D deriving (Eq, FShow, Bits);

typedef struct { 
    DecodedInst dinst;
    Bit#(32) pc;
    Bit#(32) ppc;
    Bit#(1) epoch;
    Bit#(32) rv1; 
    Bit#(32) rv2; 
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
    } D2E deriving (Eq, FShow, Bits);

typedef struct { 
    MemBusiness mem_business;
    Bit#(32) data;
    DecodedInst dinst;
    KonataId k_id; // <- This is a unique identifier per instructions, for logging purposes
} E2W deriving (Eq, FShow, Bits);

module mkScoreboard(Scoreboardinterface);
    Vector#(32, Ehr#(3, Bool)) data_hazards <- replicateM(mkEhr(False));

    method ActionValue#(Bool) search1(Bit#(5) index);
        return index == 0 ? False : data_hazards[index][2];
    endmethod
    method ActionValue#(Bool) search2(Bit#(5) index);
        return index == 0 ? False : data_hazards[index][2];
    endmethod

    method Action insert(Bit#(5) index);
        if (index != 0) begin
            data_hazards[index][2] <= True;
        end 
    endmethod
    method Action remove1(Bit#(5) index);
        if (index != 0) begin
            data_hazards[index][0] <= False;
        end 
    endmethod
    method Action remove2(Bit#(5) index);
        if (index != 0) begin
            data_hazards[index][1] <= False;
        end 
    endmethod
endmodule
module mkBypassReg(BypassRegInt);
    Vector#(32, Ehr#(2, Bit#(32))) registers <- replicateM(mkEhr(0));

    method ActionValue#(Bit#(32)) read1(Bit#(5) index);
        return index == 0 ? 0 : registers[index][1];
    endmethod
    method ActionValue#(Bit#(32)) read2(Bit#(5) index);
        return index == 0 ? 0 : registers[index][1];
    endmethod

    method Action write(Bit#(5) index, Bit#(32) value);
        if (index != 0) begin
            registers[index][0] <= value;
        end
    endmethod
endmodule

(* synthesize *)
module mkpipelined(RVIfc);
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

    // Make this an interface
    Scoreboardinterface sb <- mkScoreboard;

    Ehr#(3, Bit#(32)) redirect_pc <- mkEhr(32'h0000000);
    Ehr#(3, Bool) redirect_pc_valid <- mkEhr(False);
    

    Reg#(Bit#(32)) pc <- mkReg(32'h0000000);
    Ehr#(2, Bit#(1)) epoch <- mkEhr(0);

    BypassRegInt rf <- mkBypassReg;
    //Vector#(32, Ehr#(2, Bit#(32))) rf <- replicateM(mkEhr(0));

	// Code to support Konata visualization
    String dumpFile = "output.log" ;
    let lfh <- mkReg(InvalidFile);
	Reg#(KonataId) fresh_id <- mkReg(0);
	Reg#(KonataId) commit_id <- mkReg(0);

	FIFO#(KonataId) retired <- mkFIFO;
	FIFO#(KonataId) squashed <- mkFIFO;
    Bool debug = False;

    
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
		
    rule fetch if (!starting);
        Bit#(32) pc_fetched = ?;
        Bit#(32) ppc = pc;

        if (redirect_pc_valid[2]) begin
            let addr = redirect_pc[2];
            redirect_pc_valid[2] <= False;
            pc_fetched = addr;
            pc <= addr + 4;
            ppc = addr + 4;
        end
        else begin
            pc_fetched = pc;
            pc <= pc + 4;
            ppc = pc + 4;
        end
	    if(debug) $display("Fetch %x", pc_fetched);

        // You should put the pc that you fetch in pc_fetched
        // Below is the code to support Konata's visualization
		let iid <- fetch1Konata(lfh, fresh_id, 0);
        labelKonataLeft(lfh, iid, $format("PC %x",pc_fetched));
        // TODO implement fetch
        let req = Mem {byte_en : 0,
			   addr : pc_fetched,
			   data : 0};
        toImem.enq(req);
        F2D f2d_val = F2D {pc : pc_fetched,
                        ppc : ppc,
                        epoch : epoch[1],
                        k_id : iid};
        f2d.enq(f2d_val);

        // This will likely end with something like:
        // f2d.enq(F2D{ ..... k_id: iid});
        // iid is the unique identifier used by konata, that we will pass around everywhere for each instruction
    endrule

    rule decode if (!starting);
        // TODO
        let resp = fromImem.first();
        let instr = resp.data;
        let decodedInst = decodeInst(instr);

		if (debug) $display("[Decode] ", fshow(decodedInst));
        let fields = getInstFields(instr);
        let rs1_idx = fields.rs1;
        let rs2_idx = fields.rs2;
        Bool stall = False;
        let from_fetch = f2d.first();
        decodeKonata(lfh, from_fetch.k_id);

        // It seems we are ignoring index 0
        // How do we block on this?
        Bool stall1 <- sb.search1(rs1_idx);
        stall = stall || stall1;
        Bool stall2 <- sb.search2(rs2_idx);
        stall = stall || stall2;

        if (!stall) begin
            if (decodedInst.valid_rd) begin
                sb.insert(fields.rd);
            end
            fromImem.deq();
            let rs1 <- rf.read1(rs1_idx);
            let rs2 <- rf.read2(rs2_idx);

            // To add a decode event in Konata you will likely do something like:
            f2d.deq();

            D2E d2e_val = D2E {dinst : decodedInst,
                            pc : from_fetch.pc,
                            ppc : from_fetch.ppc,
                            epoch : from_fetch.epoch,
                            rv1 : rs1,
                            rv2 : rs2,
                            k_id : from_fetch.k_id};

            d2e.enq(d2e_val);

            labelKonataLeft(lfh,from_fetch.k_id, $format("Any information you would like to put in the left pane in Konata, attached to the current instruction"));
        end
    endrule

    rule execute if (!starting);
        // TODO
        let d2e_val = d2e.first();
        d2e.deq();
        let dInst = d2e_val.dinst;
		if (debug) $display("[Execute] ", fshow(dInst));
        let imm = getImmediate(dInst);
        Bool mmio = False;
        let pc = d2e_val.pc;
        let rv1 = d2e_val.rv1;
        let rv2 = d2e_val.rv2;
        let data = execALU32(dInst.inst, d2e_val.rv1, d2e_val.rv2, imm, pc);
        let isUnsigned = 0;
        let fields = getInstFields(dInst.inst);
		let funct3 = fields.funct3;
		let size = funct3[1:0];
		let addr = rv1 + imm;
		Bit#(2) offset = addr[1:0];

        // Similarly, to register an execute event for an instruction:
    	executeKonata(lfh, d2e_val.k_id);
    	// where k_id is the unique konata identifier that has been passed around that came from the fetch stage


    	// Execute is also the place where we advise you to kill mispredicted instructions
    	// (instead of Decode + Execute like in the class)
    	// When you kill (or squash) an instruction, you should register an event for Konata:
        if (d2e_val.epoch != epoch[0]) begin
            if (debug) $display("Squashing instruction %x", d2e_val.k_id);
            squashed.enq(d2e_val.k_id);
            if (dInst.valid_rd) begin
                sb.remove1(fields.rd);
            end
        end
        else begin
            if (isMemoryInst(dInst)) begin
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
                let type_mem = (dInst.inst[5] == 1) ? byte_en : 0;
                let req = Mem {byte_en : type_mem,
                        addr : addr,
                        data : data};
                if (isMMIO(addr)) begin 
                    if (debug) $display("[Execute] MMIO", fshow(req));
                    toMMIO.enq(req);
                    labelKonataLeft(lfh,d2e_val.k_id, $format(" MMIO ", fshow(req)));
                    mmio = True;
                end else begin 
                    labelKonataLeft(lfh,d2e_val.k_id, $format(" MEM ", fshow(req)));
                    toDmem.enq(req);
                end
            end
            else if (isControlInst(dInst)) begin
                    labelKonataLeft(lfh,d2e_val.k_id, $format(" Ctrl instr "));
                    data = pc + 4;
            end else begin 
                labelKonataLeft(lfh,d2e_val.k_id, $format(" Standard instr "));
            end
            // This will allow Konata to display those instructions in grey
            let controlResult = execControl32(dInst.inst, rv1, rv2, imm, pc);
            let nextPc = controlResult.nextPC;
            if (nextPc != d2e_val.ppc) begin
                redirect_pc_valid[0] <= True;
                redirect_pc[0] <= nextPc;
                epoch[0] <= epoch[0] + 1;
            end

            labelKonataLeft(lfh,d2e_val.k_id, $format(" ALU output: %x" , data));
            let mem_business = MemBusiness { isUnsigned : unpack(isUnsigned), size : size, offset : offset, mmio: mmio};
            E2W e2w_val = E2W {mem_business : mem_business, data : data, dinst : dInst, k_id : d2e_val.k_id};
            e2w.enq(e2w_val);
        end
    	
        // squashed.enq(current_inst.k_id);

    endrule

    rule writeback if (!starting);
        // TODO
        E2W e2w_val = e2w.first();
        e2w.deq();
        retired.enq(e2w_val.k_id);
        let data = e2w_val.data;
        let dInst = e2w_val.dinst;

        let fields = getInstFields(dInst.inst);
        let mem_business = e2w_val.mem_business;

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
		if(debug) $display("[Writeback]", fshow(dInst));
        if (!dInst.legal) begin
			if (debug) $display("[Writeback] Illegal Inst, Drop and fault: ", fshow(dInst));
			redirect_pc[1] <= 0;	// Fault
            redirect_pc_valid[1] <= True;
	    end
		if (dInst.valid_rd) begin
            let rd_idx = fields.rd;
            if (rd_idx != 0) begin rf.write(rd_idx, data); end
            sb.remove2(fields.rd);
		end



        // Similarly, to register an execute event for an instruction:
	   		writebackKonata(lfh,e2w_val.k_id);


	   	// In writeback is also the moment where an instruction retires (there are no more stages)
	   	// Konata requires us to register the event as well using the following: 
	endrule
		

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
