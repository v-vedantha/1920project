#!/bin/bash

echo "Testing add"
./test.sh add32
./top_pipelined

echo "Testing and"
./test.sh and32
./top_pipelined

echo "Testing or"
./test.sh or32
./top_pipelined

echo "Testing sub"
./test.sh sub32
./top_pipelined

echo "Testing xor" 
./test.sh xor32
./top_pipelined

echo "Testing hello"
./test.sh hello32
./top_pipelined

echo "Testing mul"
./test.sh mul32
./top_pipelined

echo "Testing reverse"
./test.sh reverse32
./top_pipelined

echo "Testing thelie"
./test.sh thelie32
./top_pipelined

echo "Testing thuemorse"
./test.sh thuemorse32
./top_pipelined

echo "Testing matmul"
./test.sh matmul32
timeout 300 ./top_pipelined

