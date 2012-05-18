#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include "2dadvec_kernels.cu"
#include "quadrature.h"
/* 2dadvec.cu
 * 
 * This file calls the kernels in 2dadvec_kernels.cu for the 2D advection
 * DG method.
 */

/* set quadrature 
 *
 * sets the 1d quadrature integration points and weights for the boundary integrals
 * and the 2d quadrature integration points and weights for the volume intergrals.
 */
void set_quadrature(int p,
                    float **r1, float **r2, float **w,
                    float **s1_r1, float **s1_r2,
                    float **s2_r1, float **s2_r2,
                    float **s3_r1, float **s3_r2,
                    float **oned_w, int *n_quad, int *n_quad1d) {
    int i;
    /*
     * The sides are mapped to the canonical element, so we want the integration points
     * for the boundary integrals for sides s1, s2, and s3 as shown below:

     r2     |\
     ^      | \
     |      |  \
     |      |   \
     |   s3 |    \ s2
     |      |     \
     |      |      \
     |      |       \
     |      |________\
     |         s1
     |
     ------------------------> r1

    *
    */
    switch (p) {
        case 0: *n_quad = 1;
                *n_quad1d = 1;
                break;
        case 1: *n_quad = 3;
                *n_quad1d = 2;
                break;
        case 2: *n_quad = 4;
                *n_quad1d = 3;
                break;
        case 3: *n_quad = 6 ;
                *n_quad1d = 4;
                break;
        case 4: *n_quad = 7;
                *n_quad1d = 5;
                break;
        case 5: *n_quad = 12;
                *n_quad1d = 6;
                break;
        case 6: *n_quad = 13;
                *n_quad1d = 7;
                break;
        case 7: *n_quad = 16;
                *n_quad1d = 8;
                break;
        case 8: *n_quad = 19;
                *n_quad1d = 9;
                break;
        case 9: *n_quad = 25;
                *n_quad1d = 10;
                break;
    }
    // allocate integration points
    *r1 = (float *) malloc(*n_quad * sizeof(float));
    *r2 = (float *) malloc(*n_quad * sizeof(float));
    *w  =  (float *) malloc(*n_quad * sizeof(float));

    *s1_r1 = (float *) malloc(*n_quad1d * sizeof(float));
    *s1_r2 = (float *) malloc(*n_quad1d * sizeof(float));
    *s2_r1 = (float *) malloc(*n_quad1d * sizeof(float));
    *s2_r2 = (float *) malloc(*n_quad1d * sizeof(float));
    *s3_r1 = (float *) malloc(*n_quad1d * sizeof(float));
    *s3_r2 = (float *) malloc(*n_quad1d * sizeof(float));
    *oned_w = (float *) malloc(*n_quad1d * sizeof(float));

    // set 2D quadrature rules
    for (i = 0; i < *n_quad; i+=3) {
        (*r1)[i] = quad_2d[p][i];
        (*r2)[i] = quad_2d[p][i+1];
        (*w) [i] = quad_2d[p][i+2];
    }

    // set 1D quadrature rules
    // TODO: there's an obvious more efficient way of doing this:
    //       just store 0.5 * quad_1d[p][i] and reuse it depending on the side
    for (i = 0; i < *n_quad1d; i+=2) {
        (*s1_r1)[i] = 0.5 * quad_1d[p][i] + 0.5;
        (*s1_r2)[i] = 0;

        (*s2_r1)[i] = 0.5 * quad_1d[p][i] + 0.5;
        (*s2_r2)[i] = 0.5 * quad_1d[p][i] + 0.5;

        (*s3_r1)[i] = 0;
        (*s3_r2)[i] = 0.5 * quad_1d[p][i] + 0.5;

        (*oned_w)[i] = 0.5 * quad_1d[p][i+1];
    }

}

void checkCudaError(const char *message)
{
    cudaError_t error = cudaGetLastError();
    if(error!=cudaSuccess) {
        fprintf(stderr,"ERROR: %s: %s\n", message, cudaGetErrorString(error) );
        exit(-1);
    }
}

void read_mesh(FILE *mesh_file, 
              int *num_sides,
              int num_elem,
              float *V1x, float *V1y,
              float *V2x, float *V2y,
              float *V3x, float *V3y,
              int *left_side_number, int *right_side_number,
              float *sides_x1, float *sides_y1,
              float *sides_x2, float *sides_y2,
              int *elem_s1,  int *elem_s2, int *elem_s3,
              int *left_elem, int *right_elem) {

    int i, j, s1, s2, s3, numsides;
    char line[100];
    numsides = 0;
    // stores the number of sides this element has.
    int *total_sides = (int *) malloc(num_elem * sizeof(int));
    for (i = 0; i < num_elem; i++) {
        total_sides[i] = 0;
    }

    i = 0;
    while(fgets(line, sizeof(line), mesh_file) != NULL) {
        // these three vertices define the element
        sscanf(line, "%f %f %f %f %f %f", &V1x[i], &V1y[i], &V2x[i], &V2y[i], &V3x[i], &V3y[i]);

        // determine whether we should add these three sides or not
        s1 = 1;
        s2 = 1;
        s3 = 1;

        // scan through the existing sides to see if we already added it
        // TODO: yeah, there's a better way to do this.
        // TODO: Also, this is super sloppy. should be checking indices instead of float values.
        for (j = 0; j < numsides; j++) {
            // side 1
            if (s1 && ((sides_x1[j] == V1x[i] && sides_y1[j] == V1y[i]
             && sides_x2[j] == V2x[i] && sides_y2[j] == V2y[i]) 
            || (sides_x2[j] == V1x[i] && sides_y2[j] == V1y[i]
             && sides_x1[j] == V2x[i] && sides_y1[j] == V2y[i]))) {
                s1 = 0;
                // OK, we've added this side to element i
                right_elem[j] = i;
                // link the added side j to this element
                elem_s1[i] = j;
                right_side_number[j] = 1;
                break;
            }
        }
        for (j = 0; j < numsides; j++) {
            // side 2
            if (s2 && ((sides_x1[j] == V2x[i] && sides_y1[j] == V2y[i]
             && sides_x2[j] == V3x[i] && sides_y2[j] == V3y[i]) 
            || (sides_x2[j] == V2x[i] && sides_y2[j] == V2y[i]
             && sides_x1[j] == V3x[i] && sides_y1[j] == V3y[i]))) {
                s2 = 0;
                // OK, we've added this side to some element before; which one?
                right_elem[j] = i;
                elem_s2[i] = j;
                // link the added side to this element
                right_side_number[j] = 2;
                break;
            }
        }
        for (j = 0; j < numsides; j++) {
            // side 3
            if (s3 && ((sides_x1[j] == V1x[i] && sides_y1[j] == V1y[i]
             && sides_x2[j] == V3x[i] && sides_y2[j] == V3y[i]) 
            || (sides_x2[j] == V1x[i] && sides_y2[j] == V1y[i]
             && sides_x1[j] == V3x[i] && sides_y1[j] == V3y[i]))) {
                s3 = 0;
                // OK, we've added this side to some element before; which one?
                right_elem[j] = i;
                elem_s3[i] = j;
                // link the added side to this element
                right_side_number[j] = 3;
                break;
            }
        }
        // if we haven't added the side already, add it
        if (s1) {
            sides_x1[numsides] = V1x[i];
            sides_y1[numsides] = V1y[i];
            sides_x2[numsides] = V2x[i];
            sides_y2[numsides] = V2y[i];
            //third_x[numsides] = V3x[i];
            //third_y[numsides] = V3y[i];

            // link the added side to this element
            left_side_number[numsides] = 1;
            // and link the element to this side
            elem_s1[i] = numsides;

            // make this the left element
            left_elem[numsides] = i;
            numsides++;
        }
        if (s2) {
            sides_x1[numsides] = V2x[i];
            sides_y1[numsides] = V2y[i];
            sides_x2[numsides] = V3x[i];
            sides_y2[numsides] = V3y[i];

            // link the added side to this element
            left_side_number[numsides] = 2;
            // and link the element to this side
            elem_s2[i] = numsides;

            // make this the left element
            left_elem[numsides] = i;
            numsides++;
        }
        if (s3) {
            sides_x1[numsides] = V3x[i];
            sides_y1[numsides] = V3y[i];
            sides_x2[numsides] = V1x[i];
            sides_y2[numsides] = V1y[i];

            // link the added side to this element
            left_side_number[numsides] = 3;
            // and link the element to this side
            elem_s3[i] = numsides;

            // make this the left element
            left_elem[numsides] = i;
            numsides++;
        }
        i++;
    }
    //free(total_sides);
    *num_sides = numsides;
}

void time_integrate(float dt, int n_quad, int n_quad1d, int n_p, int num_elem, int num_sides) {
    int n_threads = 256;

    int n_blocks_elem    = (num_elem  / n_threads) + ((num_elem  % n_threads) ? 1 : 0);
    int n_blocks_sides   = (num_sides / n_threads) + ((num_sides % n_threads) ? 1 : 0);

    // stage 1
    checkCudaError("error before stage 1: eval_riemann");
    eval_riemann<<<n_blocks_sides, n_threads>>>
                    (d_c, d_left_riemann_rhs, d_right_riemann_rhs, d_J, 
                     d_s_length,
                     d_s1_r1, d_s1_r2,
                     d_s2_r1, d_s2_r2,
                     d_s3_r1, d_s3_r2,
                     d_oned_w,
                     d_left_elem, d_right_elem,
                     d_left_side_number, d_right_side_number,
                     d_Nx, d_Ny, 
                     n_quad1d, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after stage 1: eval_riemann");

    eval_quad<<<n_blocks_elem, n_threads>>>
                    (d_c, d_quad_rhs, d_r1, d_r2, d_w, 
                     d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y,
                     d_J, n_quad, n_p, num_elem);
    cudaThreadSynchronize();
    eval_rhs<<<n_blocks_elem, n_threads>>>(d_k1, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                          d_elem_s1, d_elem_s2, d_elem_s3, 
                                          d_left_elem, dt, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    float *rhs = (float *) malloc(num_elem * n_p * sizeof(float));
    cudaMemcpy(rhs, d_k1, num_elem * n_p * sizeof(float), cudaMemcpyDeviceToHost);
    for (int i = 0; i < num_elem * n_p; i++) {
        printf(" > %f \n", rhs[i]);
    }
    free(rhs);

    rk4_tempstorage<<<n_blocks_elem, n_threads>>>(d_c, d_kstar, d_k1, 0.5, n_p, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after stage 1.");

    // stage 2
    eval_riemann<<<n_blocks_sides, n_threads>>>
                    (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, d_J, 
                     d_s_length,
                     d_s1_r1, d_s1_r2,
                     d_s2_r1, d_s2_r2,
                     d_s3_r1, d_s3_r2,
                     d_oned_w, 
                     d_left_elem, d_right_elem,
                     d_left_side_number, d_right_side_number,
                     d_Nx, d_Ny, 
                     n_quad1d, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    eval_quad<<<n_blocks_elem, n_threads>>>
                    (d_c, d_quad_rhs, d_r1, d_r2, d_w, 
                     d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y,
                     d_J, n_quad, n_p, num_elem);
    cudaThreadSynchronize();

    eval_rhs<<<n_blocks_elem, n_threads>>>(d_k2, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs,
                                          d_elem_s1, d_elem_s2, d_elem_s3, 
                                          d_left_elem, dt, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    rk4_tempstorage<<<n_blocks_elem, n_threads>>>(d_c, d_kstar, d_k2, 0.5, n_p, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after stage 2.");

    // stage 3
    eval_riemann<<<n_blocks_sides, n_threads>>>
                    (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, d_J, 
                     d_s_length,
                     d_s1_r1, d_s1_r2,
                     d_s2_r1, d_s2_r2,
                     d_s3_r1, d_s3_r2,
                     d_oned_w, 
                     d_left_elem, d_right_elem,
                     d_left_side_number, d_right_side_number,
                     d_Nx, d_Ny, 
                     n_quad1d, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    eval_quad<<<n_blocks_elem, n_threads>>>
                    (d_c, d_quad_rhs, d_r1, d_r2, d_w, 
                     d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y,
                     d_J, n_quad, n_p, num_elem);
    cudaThreadSynchronize();

    eval_rhs<<<n_blocks_elem, n_threads>>>(d_k3, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                          d_elem_s1, d_elem_s2, d_elem_s3, 
                                          d_left_elem, dt, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    rk4_tempstorage<<<n_blocks_elem, n_threads>>>(d_c, d_kstar, d_k3, 1.0, n_p, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after stage 3.");

    // stage 4
    eval_riemann<<<n_blocks_sides, n_threads>>>
                    (d_kstar, d_left_riemann_rhs, d_right_riemann_rhs, d_J, 
                     d_s_length,
                     d_s1_r1, d_s1_r2,
                     d_s2_r1, d_s2_r2,
                     d_s3_r1, d_s3_r2,
                     d_oned_w, 
                     d_left_elem, d_right_elem,
                     d_left_side_number, d_right_side_number,
                     d_Nx, d_Ny, 
                     n_quad1d, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    eval_quad<<<n_blocks_elem, n_threads>>>
                    (d_c, d_quad_rhs, d_r1, d_r2, d_w, 
                     d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y,
                     d_J, n_quad, n_p, num_elem);
    cudaThreadSynchronize();

    eval_rhs<<<n_blocks_elem, n_threads>>>(d_k4, d_quad_rhs, d_left_riemann_rhs, d_right_riemann_rhs, 
                                          d_elem_s1, d_elem_s2, d_elem_s3, 
                                          d_left_elem, dt, n_p, num_sides, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after stage 4.");
    
    // final stage
    rk4<<<n_blocks_elem, n_threads>>>(d_c, d_k1, d_k2, d_k3, d_k4, n_p, num_elem);
    cudaThreadSynchronize();

    checkCudaError("error after final stage.");
}

void init_gpu(int num_elem, int num_sides, int n_p,
              float *V1x, float *V1y, 
              float *V2x, float *V2y, 
              float *V3x, float *V3y, 
              int *left_side_number, int *right_side_number,
              float *sides_x1, float *sides_y1,
              float *sides_x2, float *sides_y2,
              int *elem_s1, int *elem_s2, int *elem_s3,
              int *left_elem, int *right_elem) {
    checkCudaError("error before init.");
    cudaDeviceReset();

    // allocate allllllllllll the memory.
    // TODO: this takes a really really long time on valor.
    cudaMalloc((void **) &d_c,        num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_quad_rhs, num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_left_riemann_rhs,  num_sides * n_p * sizeof(float));
    cudaMalloc((void **) &d_right_riemann_rhs, num_sides * n_p * sizeof(float));

    cudaMalloc((void **) &d_kstar, num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_k1, num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_k2, num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_k3, num_elem * n_p * sizeof(float));
    cudaMalloc((void **) &d_k4, num_elem * n_p * sizeof(float));

    cudaMalloc((void **) &d_r1, n_p * sizeof(float));
    cudaMalloc((void **) &d_r2, n_p * sizeof(float));
    cudaMalloc((void **) &d_w , n_p * sizeof(float));

    cudaMalloc((void **) &d_oned_w, n_p * sizeof(float));

    cudaMalloc((void **) &d_J, num_elem * sizeof(float));
    cudaMalloc((void **) &d_s_length, num_sides * sizeof(float));

    cudaMalloc((void **) &d_s_V1x, num_sides * sizeof(float));
    cudaMalloc((void **) &d_s_V2x, num_sides * sizeof(float));
    cudaMalloc((void **) &d_s_V1y, num_sides * sizeof(float));
    cudaMalloc((void **) &d_s_V2y, num_sides * sizeof(float));

    cudaMalloc((void **) &d_elem_s1, num_elem * sizeof(int));
    cudaMalloc((void **) &d_elem_s2, num_elem * sizeof(int));
    cudaMalloc((void **) &d_elem_s3, num_elem * sizeof(int));

    cudaMalloc((void **) &d_Uv1, num_elem * sizeof(float));
    cudaMalloc((void **) &d_Uv2, num_elem * sizeof(float));
    cudaMalloc((void **) &d_Uv3, num_elem * sizeof(float));

    cudaMalloc((void **) &d_V1x, num_elem * sizeof(float));
    cudaMalloc((void **) &d_V1y, num_elem * sizeof(float));
    cudaMalloc((void **) &d_V2x, num_elem * sizeof(float));
    cudaMalloc((void **) &d_V2y, num_elem * sizeof(float));
    cudaMalloc((void **) &d_V3x, num_elem * sizeof(float));
    cudaMalloc((void **) &d_V3y, num_elem * sizeof(float));

    cudaMalloc((void **) &d_s1_r1, n_p * sizeof(float));
    cudaMalloc((void **) &d_s1_r2, n_p * sizeof(float));
    cudaMalloc((void **) &d_s2_r1, n_p * sizeof(float));
    cudaMalloc((void **) &d_s2_r2, n_p * sizeof(float));
    cudaMalloc((void **) &d_s3_r1, n_p * sizeof(float));
    cudaMalloc((void **) &d_s3_r2, n_p * sizeof(float));
    
    cudaMalloc((void **) &d_left_side_number , num_sides * sizeof(int));
    cudaMalloc((void **) &d_right_side_number, num_sides * sizeof(int));

    cudaMalloc((void **) &d_Nx, num_sides * sizeof(float));
    cudaMalloc((void **) &d_Ny, num_sides * sizeof(float));

    cudaMalloc((void **) &d_right_elem, num_sides * sizeof(int));
    cudaMalloc((void **) &d_left_elem , num_sides * sizeof(int));

    // set d_c to 0 not necessary
    //cudaMemset(d_c, 0., num_elem * n_p * sizeof(float));
    cudaMemset(d_quad_rhs, 0., num_elem * n_p * sizeof(float));

    // copy over data
    cudaMemcpy(d_s_V1x, sides_x1, num_sides * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s_V1y, sides_y1, num_sides * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s_V2x, sides_x2, num_sides * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s_V2y, sides_y2, num_sides * sizeof(float), cudaMemcpyHostToDevice);

    cudaMemcpy(d_left_side_number , left_side_number , num_elem * sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_right_side_number, right_side_number, num_elem * sizeof(int), cudaMemcpyHostToDevice);

    cudaMemcpy(d_elem_s1, elem_s1, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_elem_s2, elem_s2, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_elem_s3, elem_s3, num_elem * sizeof(float), cudaMemcpyHostToDevice);

    cudaMemcpy(d_V1x, V1x, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_V1y, V1y, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_V2x, V2x, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_V2y, V2y, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_V3x, V3x, num_elem * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_V3y, V3y, num_elem * sizeof(float), cudaMemcpyHostToDevice);

    cudaMemcpy(d_left_elem , left_elem , num_sides * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_right_elem, right_elem, num_sides * sizeof(float), cudaMemcpyHostToDevice);
}

void free_gpu() {
    cudaFree(d_c);
    cudaFree(d_quad_rhs);
    cudaFree(d_left_riemann_rhs);
    cudaFree(d_right_riemann_rhs);

    cudaFree(d_kstar);
    cudaFree(d_k1);
    cudaFree(d_k2);
    cudaFree(d_k3);
    cudaFree(d_k4);

    cudaFree(d_r1);
    cudaFree(d_r2);
    cudaFree(d_w);

    cudaFree(d_oned_w);

    cudaFree(d_J);
    cudaFree(d_s_length);

    cudaFree(d_s_V1x);
    cudaFree(d_s_V2x);
    cudaFree(d_s_V1y);
    cudaFree(d_s_V2y);

    cudaFree(d_elem_s1);
    cudaFree(d_elem_s2);
    cudaFree(d_elem_s3);

    cudaFree(d_Uv1);
    cudaFree(d_Uv2);
    cudaFree(d_Uv3);

    cudaFree(d_V1x);
    cudaFree(d_V1y);
    cudaFree(d_V2x);
    cudaFree(d_V2y);
    cudaFree(d_V3x);
    cudaFree(d_V3y);

    cudaFree(d_s1_r1);
    cudaFree(d_s1_r2);
    cudaFree(d_s2_r1);
    cudaFree(d_s2_r2);
    cudaFree(d_s3_r1);
    cudaFree(d_s3_r2);
    
    cudaFree(d_left_side_number);
    cudaFree(d_right_side_number);

    cudaFree(d_Nx);
    cudaFree(d_Ny);

    cudaFree(d_right_elem);
    cudaFree(d_left_elem);
}

void usage_error() {
    printf("\nUsage: dgcuda [OPTIONS] [MESH] [OUTFILE]\n");
    printf(" Options: [-n] Order of polynomial approximation.\n");
}

int main(int argc, char *argv[]) {
    checkCudaError("error before start.");
    int num_elem, num_sides;
    int n_threads, n_blocks_elem, n_blocks_sides;
    int i, n, n_p, t, n_quad, n_quad1d;

    float dot, x, y, third_x, third_y, left_x, left_y, length;
    float dt; 
    float *Nx, *Ny;
    float *V1x, *V1y, *V2x, *V2y, *V3x, *V3y;
    float *sides_x1, *sides_x2;
    float *sides_y1, *sides_y2;

    float *r1, *r2, *w;

    float *s1_r1, *s1_r2, *s2_r1, *s2_r2, *s3_r1, *s3_r2;
    float *oned_w;

    int *left_elem, *right_elem;
    int *elem_s1, *elem_s2, *elem_s3;
    int *left_side_number, *right_side_number;

    FILE *mesh_file, *out_file;

    char line[100];
    char *mesh_filename;
    char *out_filename;

    float *Uv1, *Uv2, *Uv3;
    // read command line input
    if (argc < 5) {
        usage_error();
        return 1;
    }
    for (i = 0; i < argc; i++) {
        // order of polynomial
        if (strcmp(argv[i], "-n") == 0) {
            if (i + 1 < argc) {
                n = atoi(argv[i+1]);
                if (n < 0 || n > 1) {
                    usage_error();
                    return 1;
                }
            } else {
                usage_error();
                return 1;
            }
        }
    } 

    // second last argument is filename
    mesh_filename = argv[argc - 2];
    // last argument is outfilename
    out_filename  = argv[argc - 1];

    // set the order of the approximation & timestep
    n_p = (n + 1) * (n + 2) / 2;
    dt  = 0.001;

    // open the mesh to get num_elem for allocations
    mesh_file = fopen(mesh_filename, "r");
    out_file  = fopen(out_filename , "w");
    if (!mesh_file) {
        printf("\nERROR: mesh file not found.\n");
        return 1;
    }
    fgets(line, 100, mesh_file);
    sscanf(line, "%i", &num_elem);

    // allocate vertex points
    V1x = (float *) malloc(num_elem * sizeof(float));
    V1y = (float *) malloc(num_elem * sizeof(float));
    V2x = (float *) malloc(num_elem * sizeof(float));
    V2y = (float *) malloc(num_elem * sizeof(float));
    V3x = (float *) malloc(num_elem * sizeof(float));
    V3y = (float *) malloc(num_elem * sizeof(float));

    elem_s1 = (int *) malloc(num_elem * sizeof(int));
    elem_s2 = (int *) malloc(num_elem * sizeof(int));
    elem_s3 = (int *) malloc(num_elem * sizeof(int));

    // TODO: these are too big; should be a way to figure out how many we actually need
    left_side_number  = (int *)   malloc(3*num_elem * sizeof(int));
    right_side_number = (int *)   malloc(3*num_elem * sizeof(int));

    sides_x1    = (float *) malloc(3*num_elem * sizeof(float));
    sides_x2    = (float *) malloc(3*num_elem * sizeof(float));
    sides_y1    = (float *) malloc(3*num_elem * sizeof(float));
    sides_y2    = (float *) malloc(3*num_elem * sizeof(float)); 
    left_elem   = (int *) malloc(3*num_elem * sizeof(int));
    right_elem  = (int *) malloc(3*num_elem * sizeof(int));

    for (i = 0; i < 3*num_elem; i++) {
        right_elem[i] = -1;
    }
    // read in the mesh and make all the mappings
    read_mesh(mesh_file, &num_sides, num_elem,
                         V1x, V1y, V2x, V2y, V3x, V3y,
                         left_side_number, right_side_number,
                         sides_x1, sides_y1, 
                         sides_x2, sides_y2, 
                         elem_s1, elem_s2, elem_s3,
                         left_elem, right_elem);

    // close the file
    fclose(mesh_file);

    Nx = (float *) malloc(num_sides * sizeof(float));
    Ny = (float *) malloc(num_sides * sizeof(float));

    // ugh, this is so dumb. the stupid gpu (on gale) won't 
    // reverse the normal vectors all the time. it'll sometimes do it,
    // sometimes not. fucking ridiculous. so here it's done on the cpu.
    for (i = 0; i < num_sides; i++) {
       
        x = sides_x2[i] - sides_x1[i];
        y = sides_y2[i] - sides_y1[i];

        switch(left_side_number[i]) {
            case 1: 
                left_x = V3x[left_elem[i]];
                left_y = V3y[left_elem[i]];

                break;
            case 2:
                left_x = V1x[left_elem[i]];
                left_y = V1y[left_elem[i]];

                break;
            case 3:
                left_x = V2x[left_elem[i]];
                left_y = V2y[left_elem[i]];

                break;
        }
        third_x = left_x - (sides_x1[i] + sides_x2[i]) / 2.;
        third_y = left_y - (sides_y1[i] + sides_y2[i]) / 2.;
    
        // find the dot product between the normal vector and the third vetrex point
        length = sqrtf(powf(x,2) + powf(y,2));
        dot = -y*third_x + x*third_y;

        // if the dot product is negative, reverse direction
        if (dot < 0) {
            length *= -1;
        }

        Nx[i] = -y / length;
        Ny[i] =  x / length;
    }

    // initialize the gpu
    init_gpu(num_elem, num_sides, n_p,
             V1x, V1y, V2x, V2y, V3x, V3y,
             left_side_number, right_side_number,
             sides_x1, sides_y1,
             sides_x2, sides_y2, 
             elem_s1, elem_s2, elem_s3,
             left_elem, right_elem);

    n_threads        = 128;
    n_blocks_elem    = (num_elem  / n_threads) + ((num_elem  % n_threads) ? 1 : 0);
    n_blocks_sides   = (num_sides / n_threads) + ((num_sides % n_threads) ? 1 : 0);

    // pre computations
    preval_side_length<<<n_blocks_sides, n_threads>>>(d_s_length, d_s_V1x, d_s_V1y, d_s_V2x, d_s_V2y, 
                                                      num_sides); 
    preval_jacobian<<<n_blocks_elem, n_threads>>>(d_J, d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y, num_elem); 
    //preval_normals<<<n_blocks_sides, n_threads>>>(d_Nx, d_Ny, 
                                                  //d_s_V1x, d_s_V1y, d_s_V2x, d_s_V2y,
                                                  //d_V1x, d_V1y, 
                                                  //d_V2x, d_V2y, 
                                                  //d_V3x, d_V3y, 
                                                  //d_left_elem, d_left_side_number, num_sides); 
    checkCudaError("error after prevals.");

    cudaMemcpy(d_Nx, Nx, num_sides * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_Ny, Ny, num_sides * sizeof(float), cudaMemcpyHostToDevice);

    // get the correct quadrature rules for this scheme
    set_quadrature(n, &r1, &r2, &w, 
                   &s1_r1, &s1_r2, 
                   &s2_r1, &s2_r2, 
                   &s3_r1, &s3_r2, 
                   &oned_w, &n_quad, &n_quad1d);

    checkCudaError("error before quadrature copy.");

    cudaMemcpy(d_r1, r1, n_quad * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_r2, r2, n_quad * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_w , w , n_quad * sizeof(float), cudaMemcpyHostToDevice);

    cudaMemcpy(d_s1_r1, s1_r1, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s1_r2, s1_r2, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s2_r1, s2_r1, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s2_r2, s2_r2, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s3_r1, s3_r1, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_s3_r2, s3_r2, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);

    cudaMemcpy(d_oned_w, oned_w, n_quad1d * sizeof(float), cudaMemcpyHostToDevice);

    // initial conditions
    init_conditions<<<n_blocks_elem, n_threads>>>(d_c, d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y,
                    d_r1, d_r2, d_w, n_quad, n_p, num_elem);
    checkCudaError("error after initial conditions.");

    Uv1 = (float *) malloc(num_elem * sizeof(float));
    Uv2 = (float *) malloc(num_elem * sizeof(float));
    Uv3 = (float *) malloc(num_elem * sizeof(float));

    printf("Computing...\n");
    printf(" > %i degree polynomial interpolation\n", n);
    printf(" > %i elements\n", num_elem);
    printf(" > %i sides\n", num_sides);

    checkCudaError("error before time integration.");
    fprintf(out_file, "View \"Exported field \" {\n");
    for (t = 0; t < 1; t++) {
        // time integration
        time_integrate(dt, n_quad, n_quad1d, n_p, num_elem, num_sides);

        // evaluate at the vertex points and copy over data
        eval_u<<<n_blocks_elem, n_threads>>>(d_c, d_V1x, d_V1y, d_V2x, d_V2y, d_V3x, d_V3y, d_Uv1, d_Uv2, d_Uv3, num_elem, n_p);
        cudaMemcpy(Uv1, d_Uv1, num_elem * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(Uv2, d_Uv1, num_elem * sizeof(float), cudaMemcpyDeviceToHost);
        cudaMemcpy(Uv3, d_Uv1, num_elem * sizeof(float), cudaMemcpyDeviceToHost);

        // write data to file
        // TODO: this will output multiple vertices values. does gmsh care? i dunno...
        for (i = 0; i < num_elem; i++) {
            fprintf(out_file, "ST (%f,%f,0,%f,%f,0,%f,%f,0) {%f,%f,%f};\n", 
                                   V1x[i], V1y[i], V2x[i], V2y[i], V3x[i], V3y[i],
                                   Uv1[i], Uv2[i], Uv3[i]);
        }
    }
    fprintf(out_file,"};");

    // close the output file
    fclose(out_file);

    // free variables
    free_gpu();
    
    free(Uv1);
    free(Uv2);
    free(Uv3);

    free(V1x);
    free(V1y);
    free(V2x);
    free(V2y);
    free(V3x);
    free(V3y);

    free(elem_s1);
    free(elem_s2);
    free(elem_s3);

    free(sides_x1);
    free(sides_x2);
    free(sides_y1);
    free(sides_y2);

    free(left_elem);
    free(right_elem);
    free(left_side_number);
    free(right_side_number);

    free(r1);
    free(r2);
    free(w);
    free(s1_r1);
    free(s1_r2);
    free(s2_r1);
    free(s2_r2);
    free(s3_r1);
    free(s3_r2);
    free(oned_w);

    free(Nx);
    free(Ny);

    return 0;
}
