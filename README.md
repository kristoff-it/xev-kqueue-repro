# xev-kqueue-repro



Open two netcat listeners:
```
nc -luk 0.0.0.0 1993
nc -luk 0.0.0.0 1994
```

Run:
```
zig build run
```


Observe:

1. Two write calls are scheduled
2. Only one write call has its success callback triggered
3. Only one of the two netcat instances actually receives packets


