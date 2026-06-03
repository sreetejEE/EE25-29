#include<stdio.h>
#include<stdlib.h>
#include<math.h>

#define EPS 1e-10 // to prevent division by zero
#define MAX 150 // the maximum times to be iterated for obtaining each singular value 

//Function to normalize a vector 
void normalization(double *v,int n)
{
    double mag = 0.0;
    for(int i=0;i<n;i++)
    {
        mag = mag + v[i]*v[i]; // sum of squares
    }
    mag = sqrt(mag);
    if(mag > EPS) 
    {
        for (int i=0;i<n;i++)
        {
            v[i] = v[i]/mag;//dividing each element with mag , results in v of length 1
        }
    }
}

//function for multiplying matrix with vector
void matrix_vec(const double *M,const double *v,int m , int n,double *result)
{
    for(int i=0;i<m;i++)
    {
        result[i]=0.0;
        for(int j=0 ; j <n ;j++)
        {
            result[i] = result[i] + M[i*n+j]*v[j]; // stores the result in another vector result[i]
        }
    }
}

//the implementation of power iteration
double pow_iter(const double *N,int n,double *v)
{
    for (int i=0;i<n;i++)
    {
        v[i]=(double)rand()/RAND_MAX ;//getting rand values from defined functions in stdlib
    }
    normalization(v,n);
    double *x = malloc(n*sizeof(double));

    for(int a=0;a<MAX;a++)
    {
        matrix_vec(N,v,n,n,x);
        normalization(x,n);
        for(int i=0;i<n;i++)
        {
            v[i]=x[i];
        }
    }
    matrix_vec(N,v,n,n,x);
    double eigen_val=0.0;
    for(int i=0;i<n;i++)
    {
        eigen_val = eigen_val + v[i]*x[i]; //finding largest eigen value
    }
    free(x);
    return eigen_val;
}

//to find the reconstructed image matrix
void svd_reconstructed(const double *A,int r,int c,int k,double *A_recon)
{   //allocating space for use
    double *B=malloc(c * c *sizeof(double));
    double *B1=malloc(c*c*sizeof(double));
    double *U=calloc(r*k,sizeof(double));
    double *V=calloc(c*k,sizeof(double));
    double *S=calloc(k,sizeof(double));
    double *v=malloc(c*sizeof(double));
    double *u=malloc(r*sizeof(double));

// getting B=A^TA by multiplying A^T with A
    for(int i=0 ; i<c ;i++)
    {
        for(int j=0 ; j< c ;j++)
        {
            double sum =0.0;
            for (int p = 0;p<r;p++)
            {
                sum = sum + A[p*c+i]*A[p*c+j];
            }
            B[i*c+j]=sum ;
        }
    }

    for(int i=0;i<c*c;i++)
    {
        B1[i]=B[i]; // taking B1 same as B for deflation
    }

    for(int t=0;t<k;t++)
    {
        double eigen_val = pow_iter(B1,c,v);
        S[t]=sqrt(eigen_val); // storing singular values
        for(int i=0;i<c;i++)
        {
            V[i*k+t]=v[i];
        }
        for(int i=0 ; i<c;i++)
        {
            for(int j=0;j<c;j++)
            {
                B1[i*c+j] = B1[i*c+j] - (eigen_val * v[i] *v[j]); //Deflation process
            }
        }
    }

    for(int p=0;p<k;p++)
    {
        for(int j=0 ; j<c;j++)
        {
            v[j]=V[j*k+p];//again v[j] used for calculating u[j]
        
    }
    matrix_vec(A,v,r,c,u);
    normalization(u,r);
    for(int j=0 ; j <r ;j++)
    {
        U[j*k+p]=u[j];//storing u[j] in U
    }
    }

    for(int b =0 ;b<r ;b++)
    {
        for(int d =0 ; d<c;d++)
            {
                double sum=0.0;
                for(int i=0;i<k;i++)
                {
                    sum = sum +
                    ( U[b*k+i]*S[i]*V[d*k+i] ); // USV^T = A
                }
                A_recon[b*c+d]=sum;//finding the reconstructed matrix
            }
    }

    free(B);
    free(B1);
    free(U);
    free(V);
    free(v);
    free(u);
    free(S);
//free all allocated memory 
}
