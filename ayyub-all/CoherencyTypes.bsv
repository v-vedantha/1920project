import Vector::*;
import MemTypes::*;

typedef enum {
	M, S, I
} MSI deriving (Eq, FShow, Bits);

typedef enum {
	Request, Response
} ReqRes deriving (Eq, FShow, Bits);

typedef Bit#(1) WhichCache;

typedef struct {
                Vector#(16, Word) data;
                LineAddr addr;
                MSI msi;
                ReqRes reqres;
                WhichCache whichcache;
} CoherencyMessage deriving (Eq, FShow, Bits);