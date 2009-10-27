all:
	gcc -Wall -g k-tree-gen.c -o k-tree-gen 
	gcc -Wall -g k-tree-trav.c -o k-tree-trav 

	cp fs-metadata.sh k-thread.sh k-tree-gen k-tree-trav ../../bin

clean:
	rm -f k-tree-gen k-tree-trav *.o
