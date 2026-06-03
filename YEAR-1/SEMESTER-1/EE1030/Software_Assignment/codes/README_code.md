##  Image Compression via Truncated SVD (Power Iteration)
Hybrid **C + Python** implementation for compressing grayscale images using **Power Iteration–based SVD**.

### 1) Install Python dependencies
```pip install numpy pillow matplotlib```

### 2) C -driver
Write a C code (svd_compression.c)  implemeting your algorithm

### 3) Compile C to a shared library (from inside ./codes)
cd codes
``` gcc -shared -o svd_compression.so -fPIC svd_compression.c -lm ```

**-fPIC** - positive independent code for shared library

**-lm** - links math library

### 4)Python-driver
Write python code using libs *numpy* , *ctypes* , *PILL* , *matplotlib* for loading image and to plot reconstructed image.
 
### 5) Run Python driver

```python3 main.py ``` 


