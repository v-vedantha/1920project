#!/bin/bash

echo "Testing add"
./test.sh add32
./multicore

echo "Testing and"
./test.sh and32
./multicore

echo "Testing or"
./test.sh or32
./multicore

echo "Testing sub"
./test.sh sub32
./multicore

echo "Testing xor" 
./test.sh xor32
./multicore

echo "Testing hello"
./test.sh hello32
./multicore

echo "Testing mul"
./test.sh mul32
./multicore

echo "Testing reverse"
./test.sh reverse32
./multicore

echo "Testing thelie"
./test.sh thelie32
./multicore

echo "Testing thuemorse"
./test.sh thuemorse32
./multicore

# echo "Testing matmul"
# ./test.sh matmul32
# ./multicore

echo "Testing mc_print.c"
./test.sh mc_print32
./multicore

echo "Testing mc_hello.c"
./test.sh mc_hello32
./multicore

echo "Testing mc_produce_consume.c"
./test.sh mc_produce_consume32
./multicore

echo "Testing mc_multiply.c"
./test.sh mc_multiply32
./median
