
example using actors tmillions:

```
cd actors
nim c -d:release -d:usemalloc --mm:arc tests/tmillions.nim
```

```
make 
LD_PRELOAD=./libmemgraph.so /tmp/tmillions
```

