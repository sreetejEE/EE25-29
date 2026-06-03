# Image Compression Using Truncated SVD (Power Iteration)

##  Project Overview

### **Introduction**
The project aims to perform **image compression using Truncated Singular Value Decomposition (SVD)**, implemented via the **Power Iteration algorithm**.
In this approach, a grayscale image is represented as a matrix of pixel intensities. By using SVD, the image can be approximated using only the most significant singular values and vectors, thus achieving compression without major loss of visual quality.

##  Procedure

### **1. Image Representation**
Convert the grayscale image into a matrix
where each entry represents a pixel intensity.

### **2. Power Iteration for SVD**
Use the **Power Iteration** method to find the largest singular value and corresponding singular vectors.
**Deflate** the matrix and repeat the process to obtain the top \( k \) singular values.
Normalize vectors at each iteration to ensure numerical stability.

### **3. Reconstruction**
Form the rank-\( k \) approximation,
The matrix is reconstructed

### **4. Error Analysis**
Compute the **Frobenius error** to measure reconstruction accuracy

### **5. Visualization**
Display both **original** and **reconstructed** images using Python libraries like:
`matplotlib`and 
`PIL`

This helps visually compare the compression levels for different values of \( k \).


## Conclusion
The **Power Iteration–based SVD** approach effectively captures the dominant image features with minimal computation.
As \( k \) increases, image quality improves while compression efficiency decreases.
This method demonstrates the practical balance between **computational efficiency** and **image fidelity**.
