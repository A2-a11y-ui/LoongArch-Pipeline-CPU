# Independent algorithm-level trace checker; NOT a Verilog simulation.
# Reconstructs expected hit/miss counts for 256B 2-way LRU.
class Cache:
    def __init__(self, sets, ways):
        self.lines = [[] for _ in range(sets)]  # LRU->MRU
        self.sets, self.ways = sets, ways
        self.hits = self.misses = 0
    def access(self, addr):
        line=addr//16
        idx=line%self.sets
        tag=line//self.sets
        x=self.lines[idx]
        if tag in x:
            self.hits+=1
            x.remove(tag)
            x.append(tag)
        else:
            self.misses+=1
            if len(x)==self.ways:
                x.pop(0)
            x.append(tag)

def trace(p):
    if p==0: return [(i%32)*4 for i in range(96)]
    if p==1: return [(i%4)*4 for i in range(64)]
    if p==2: return [0 if i%2==0 else 0x100 for i in range(32)]
    return [0,0x80,0,0x100,0,0x80]
for p in range(4):
    line=trace(p)
    a=Cache(16,1)
    b=Cache(8,2)
    for x in line:
        a.access(x);b.access(x)
    print(f"pattern={p} requests={len(line)} DM hit/miss={a.hits}/{a.misses} 2way hit/miss={b.hits}/{b.misses}")
    expected={0:(88,8),1:(63,1),2:(30,2),3:(2,4)}[p]
    assert (b.hits,b.misses)==expected
