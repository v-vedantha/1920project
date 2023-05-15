
import RVUtil::*;
import BRAM::*;
import pipelined::*;
import FIFO::*;
import MemTypes::*;
import DCache::*;
import Vector::*;

interface AddrPred;
    method CacheAddr nap(CacheAddr pc);
    method Action update(CacheAddr pc, CacheAddr nextPC, Bool taken);
endinterface

typedef 2 K;
typedef 4 Entries;
typedef Bit#(K) Index
typedef Bit#(28) Tag;

function Tag getAddrPredictTag(CacheAddr pc);
    return pc[31:2 + K];
endfunction

function Index getAddrPredictIndex(CacheAddr pc);
    return pc[2+K:2];
endfunction

module mkBranchPredictor(AddrPred);
    Vector#(Entries, Tag) tags <- replicateM(0);
    Vector#(Entries, Bool) valid <- replicateM(False);
    Vector#(Entries, CacheAddr) nextPC <- replicateM(0);

    method Action update(CacheAddr pc, CacheAddr nextPC, Bool taken);
        Index index = getAddrPredictIndex(pc);
        Tag tag = getAddrPredictTag(pc);
        if (taken) begin
            tags[index] <= tag;
            valid[index] <= True;
            nextPC[index] <= nextPC;
        end else begin
            valid[index] <= False;
        end
    endmethod

    method CacheAddr nap(CacheAddr pc);
        Index index = getAddrPredictIndex(pc);
        Tag tag = getAddrPredictTag(pc);
        CacheAddr returnVal = 0;
        if (valid[index] && tags[index] == tag) begin
            returnVal = nextPC[index];
        end else begin
            returnVal = pc + 4;
        end

        return returnVal;
    endmethod

endmodule

