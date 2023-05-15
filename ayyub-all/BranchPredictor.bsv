
import RVUtil::*;
import BRAM::*;
import FIFO::*;
import MemTypes::*;
import DCache::*;
import Vector::*;

interface AddrPred;
    method CacheAddr nap(CacheAddr pc);
    method Action update(CacheAddr pc, CacheAddr nextPC, Bool taken);
endinterface

typedef 9 K;
typedef TExp#(K) BranchEntries;
typedef Bit#(K) BranchIndex;
typedef Bit#(TSub#(30, K)) BranchTag;

function BranchTag getAddrPredictTag(CacheAddr pc);
    return pc[31:2 + valueOf(K)];
endfunction

function BranchIndex getAddrPredictIndex(CacheAddr pc);
    return pc[2+valueOf(K) - 1:2];
endfunction

module mkBranchPredictor(AddrPred);
    Vector#(BranchEntries, Reg#(BranchTag)) tags <- replicateM(mkRegU);
    Vector#(BranchEntries, Reg#(Bool)) valid <- replicateM(mkReg(False));
    Vector#(BranchEntries, Reg#(CacheAddr)) predPC <- replicateM(mkRegU);

    method Action update(CacheAddr pc, CacheAddr nextPC, Bool taken);
        BranchIndex branchIndex = getAddrPredictIndex(pc);
        BranchTag branchTag = getAddrPredictTag(pc);
        tags[branchIndex] <= branchTag;
        valid[branchIndex] <= True;
        predPC[branchIndex] <= nextPC;
        // if (taken) begin
        // end else begin
        //     valid[branchIndex] <= False;
        // end
    endmethod

    method CacheAddr nap(CacheAddr pc);
        BranchIndex branchIndex = getAddrPredictIndex(pc);
        BranchTag branchTag = getAddrPredictTag(pc);
        CacheAddr returnVal = 0;
        if (valid[branchIndex] && tags[branchIndex] == branchTag) begin
            returnVal = predPC[branchIndex];
        end else begin
            returnVal = pc + 4;
        end

        return returnVal;
    endmethod

endmodule

