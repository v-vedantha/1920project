In the file `Cache.bsv`, you should implement the `mkCache` module. Your cache should have the following characteristics:
- It has 128 cache lines, each line is 512-bits long (and because the responses are 512-bits large, every line contains a single entry)
- It uses a writeback miss-allocate policy
- It uses a store-buffer
- You are free to design either a k-way associative (k=2,4,8) or a direct-mapped cache. If you choose a k-way associative you can pick any replacement policy you want
- You should use a BRAM to hold the content of the cache, you are free to either use a BRAM or a vector of 128 registers (or EHR) to hold the tags and the states of the lines.

In the file `MemTypes.bsv` we defined a few basic types.
You will also have to define new types for the tags and the indexes.


# Running tests

In the spirit of limiting the amount of work for this lab, we do not require you to connect the cache to a processor, instead we test the cache in isolation.

To test the cache in isolation, we have made one randomized test. It only tests functional correctness. The test does not check the sizes/kind of cache chosen, etc... all those things will be discussed during checkoffs.

The test is simply sending random requests both to your design, and to an ideal memory. The test make sure that the response obtained from your system are the same as the one returned by the ideal memory.

To run the test, you can do:

```
make
./Beveren
```
