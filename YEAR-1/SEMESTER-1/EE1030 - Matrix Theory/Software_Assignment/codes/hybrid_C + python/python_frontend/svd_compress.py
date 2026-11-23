import ctypes
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image

c_lib = ctypes.CDLL('../c_backend/./svd_compression.so') #loads the c-library

#defining the argument types 
c_lib.svd_reconstructed.argtypes=[np.ctypeslib.ndpointer(dtype=np.float64,ndim=2,flags='C_CONTIGUOUS') ,
ctypes.c_int ,
ctypes.c_int ,
ctypes.c_int , np.ctypeslib.ndpointer(dtype=np.float64,ndim=2,flags='C_CONTIGUOUS') ]

image_load = '../../../figs/original/123.jpg' #defines image_path for test_image , can be replaced it with our requirements
k=100 #defines integer k , can be replaced as per our requirements

orig_image = np.array(Image.open(image_load).convert('L'),dtype = np.float64) #converts image to array

rows ,  columns = orig_image.shape

recon_image = np.empty_like(orig_image) # same as orig_image , shape and data types

c_lib.svd_reconstructed(orig_image, rows,columns,k,recon_image)

#calculating frobenius error
error_matrix = orig_image - recon_image
squared = error_matrix ** 2
sum =np.sum(squared)
frob_error=np.sqrt(sum)
print(f"Rank of Compression(k):{k}")
print(f"Frobenius error : {frob_error:.6f}")

#plotting image
plt.figure(figsize=(6,6))
plt.subplot(1,1,1)
plt.title(f"Reconstructed image (k={k})")
plt.imshow(recon_image,cmap='gray')
plt.axis('off')

plt.show()
