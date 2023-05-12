import Vector::*;

typedef Bit#(32) Word;
typedef Vector#(16, Word) Line;
typedef Bit#(512) PackedLine;

typedef Bit#(32) CacheAddr;
typedef Bit#(26) LineAddr; // 32 - 4 (block) - 2 (multiple of 4)
typedef 2 CoreNum;
typedef Bit#(TLog#(CoreNum)) CoreID;
typedef struct { 
                Bit#(1) write;
                CacheAddr addr;
                Word data;
               } CacheReq deriving (Eq, FShow, Bits, Bounded);
typedef struct { 
                Bit#(1) write;
                LineAddr addr;
                Line data;
               } MainMemReq deriving (Eq, FShow, Bits, Bounded);

typedef Line MainMemResp;

typedef enum { M, S, I } MSI deriving( Bits, Eq, FShow );
instance Ord#(MSI);
    function Bool \< ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT);
    endfunction
    function Bool \<= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == LT) || (c == EQ);
    endfunction
    function Bool \> ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT);
    endfunction
    function Bool \>= ( MSI x, MSI y );
        let c = compare(x,y);
        return (c == GT) || (c == EQ);
    endfunction

    // This should implement M > S > I
    function Ordering compare( MSI x, MSI y );
        if( x == y ) begin
            // MM SS II
            return EQ;
        end else if( x == M || y == I) begin
            // MS MI SI
            return GT;
        end else begin
            // SM IM IS
            return LT;
        end
    endfunction

    function MSI min( MSI x, MSI y );
        if( x < y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
    function MSI max( MSI x, MSI y );
        if( x > y ) begin
            return x;
        end else begin
            return y;
        end
    endfunction
endinstance
