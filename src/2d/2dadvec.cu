#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include "2dadvec_kernels.cu"
/* 2dadvec.cu
 * 
 * This file calls the kernels in 2dadvec_kernels.cu for the 2D advection
 * DG method.
 */

void set_quadrature(int p, float *r1, float *r2, float *w) {
    switch (p) {
        case 0:
            r1[0] = 0.333333333333333;
            r2[0] = 0.333333333333333;
            w[0]  = 1.0;
            break;
        case 2:
            r1[0] = 0.166666666666666;
            r2[0] = 0.166666666666666;
            w[0]  = 0.333333333333333;
            r1[1] = 0.666666666666666;
            r2[1] = 0.166666666666666;
            w[1]  = 0.333333333333333;
            r1[2] = 0.166666666666666;
            r2[2] = 0.666666666666666;
            w[2]  = 0.333333333333333;
            break;
    }
}
/*             
  { {0.333333333333333,0.3333333333333333},-0.5625},
  { {0.6,0.2},.520833333333333 },
  { {0.2,0.6},.520833333333333 },
  { {0.2,0.2},.520833333333333 }
};

IntPt2d GQT4[6] = {
  { {0.816847572980459,0.091576213509771},0.109951743655322},
  { {0.091576213509771,0.816847572980459},0.109951743655322},
  { {0.091576213509771,0.091576213509771},0.109951743655322},
  { {0.108103018168070,0.445948490915965},0.223381589678011},
  { {0.445948490915965,0.108103018168070},0.223381589678011},
  { {0.445948490915965,0.445948490915965},0.223381589678011}
};

IntPt2d GQT5[7] = {
  { {0.333333333333333,0.333333333333333},0.225000000000000},
  { {0.797426985353087,0.101286507323456},0.125939180544827},
  { {0.101286507323456,0.797426985353087},0.125939180544827},
  { {0.101286507323456,0.101286507323456},0.125939180544827},
  { {0.470142064105115,0.059715871789770},0.132394152788506},
  { {0.059715871789770,0.470142064105115},0.132394152788506},
  { {0.470142064105115,0.470142064105115},0.132394152788506}
};

IntPt2d GQT6[12] = {
  { {0.873821971016996,0.063089014491502},0.050844906370207},
  { {0.063089014491502,0.873821971016996},0.050844906370207},
  { {0.063089014491502,0.063089014491502},0.050844906370207},
  { {0.501426509658179,0.249286745170910},0.116786275726379},
  { {0.249286745170910,0.501426509658179},0.116786275726379},
  { {0.249286745170910,0.249286745170910},0.116786275726379},
  { {0.636502499121399,0.310352451033784},0.082851075618374},
  { {0.310352451033784,0.636502499121399},0.082851075618374},
  { {0.636502499121399,0.053145049844816},0.082851075618374},
  { {0.310352451033784,0.053145049844816},0.082851075618374},
  { {0.053145049844816,0.310352451033785},0.082851075618374},
  { {0.053145049844816,0.636502499121399},0.082851075618374}
};

IntPt2d GQT7[13] = {
  { {0.333333333333333,0.333333333333333},-0.149570044467682},
  { {0.479308067841920,0.260345966079040},0.175615257433208},
  { {0.260345966079040,0.479308067841920},0.175615257433208},
  { {0.260345966079040,0.260345966079040},0.175615257433208},
  { {0.869739794195568,0.065130102902216},0.053347235608838},
  { {0.065130102902216,0.869739794195568},0.053347235608838},
  { {0.065130102902216,0.065130102902216},0.053347235608838},
  { {0.048690315425316,0.312865496004874},0.077113760890257},
  { {0.312865496004874,0.048690315425316},0.077113760890257},
  { {0.638444188569810,0.048690315425316},0.077113760890257},
  { {0.048690315425316,0.638444188569810},0.077113760890257},
  { {0.312865496004874,0.638444188569810},0.077113760890257},
  { {0.638444188569810,0.312865496004874},0.077113760890257}

};

IntPt2d GQT8[16] = {
  { {0.333333333333333,0.333333333333333},0.144315607677787},
  { {0.081414823414554,0.459292588292723},0.095091634267285},
  { {0.459292588292723,0.081414823414554},0.095091634267285},
  { {0.459292588292723,0.459292588292723},0.095091634267285},
  { {0.658861384496480,0.170569307751760},0.103217370534718},
  { {0.170569307751760,0.658861384496480},0.103217370534718},
  { {0.170569307751760,0.170569307751760},0.103217370534718},
  { {0.898905543365938,0.050547228317031},0.032458497623198},
  { {0.050547228317031,0.898905543365938},0.032458497623198},
  { {0.050547228317031,0.050547228317031},0.032458497623198},  
  { {0.008394777409958,0.728492392955404},0.027230314174435},
  { {0.728492392955404,0.008394777409958},0.027230314174435},
  { {0.263112829634638,0.008394777409958},0.027230314174435},
  { {0.008394777409958,0.263112829634638},0.027230314174435},
  { {0.263112829634638,0.728492392955404},0.027230314174435},
  { {0.728492392955404,0.263112829634638},0.027230314174435}
};

IntPt2d GQT9[19] = {
  { {0.333333333333333,0.333333333333333},0.097135796282799},
  { {0.020634961602525,0.489682519198738},0.031334700227139},
  { {0.489682519198738,0.020634961602525},0.031334700227139},
  { {0.489682519198738,0.489682519198738},0.031334700227139},
  { {0.125820817014127,0.437089591492937},0.077827541004774},
  { {0.437089591492937,0.125820817014127},0.077827541004774},
  { {0.437089591492937,0.437089591492937},0.077827541004774},
  { {0.623592928761935,0.188203535619033},0.079647738927210},
  { {0.188203535619033,0.623592928761935},0.079647738927210},
  { {0.188203535619033,0.188203535619033},0.079647738927210},
  { {0.910540973211095,0.044729513394453},0.025577675658698},
  { {0.044729513394453,0.910540973211095},0.025577675658698},
  { {0.044729513394453,0.044729513394453},0.025577675658698},
  { {0.036838412054736,0.221962989160766},0.043283539377289},
  { {0.221962989160766,0.036838412054736},0.043283539377289},
  { {0.036838412054736,0.741198598784498},0.043283539377289},
  { {0.741198598784498,0.036838412054736},0.043283539377289},
  { {0.741198598784498,0.221962989160766},0.043283539377289},
  { {0.221962989160766,0.741198598784498},0.043283539377289}
};

IntPt2d GQT10[25] = {
  { {0.333333333333333,0.333333333333333},0.090817990382754},
  { {0.028844733232685,0.485577633383657},0.036725957756467},
  { {0.485577633383657,0.028844733232685},0.036725957756467},
  { {0.485577633383657,0.485577633383657},0.036725957756467},
  { {0.781036849029926,0.109481575485037},0.045321059435528},
  { {0.109481575485037,0.781036849029926},0.045321059435528},
  { {0.109481575485037,0.109481575485037},0.045321059435528},
  { {0.141707219414880,0.307939838764121},0.072757916845420},
  { {0.307939838764121,0.141707219414880},0.072757916845420},
  { {0.307939838764121,0.550352941820999},0.072757916845420},
  { {0.550352941820999,0.307939838764121},0.072757916845420},
  { {0.550352941820999,0.141707219414880},0.072757916845420},
  { {0.141707219414880,0.550352941820999},0.072757916845420},
  { {0.025003534762686,0.246672560639903},0.028327242531057},
  { {0.246672560639903,0.025003534762686},0.028327242531057},
  { {0.025003534762686,0.728323904597411},0.028327242531057},
  { {0.728323904597411,0.025003534762686},0.028327242531057},
  { {0.728323904597411,0.246672560639903},0.028327242531057},
  { {0.246672560639903,0.728323904597411},0.028327242531057},
  { {0.009540815400299,0.066803251012200},0.009421666963733},
  { {0.066803251012200,0.009540815400299},0.009421666963733},
  { {0.066803251012200,0.923655933587500},0.009421666963733},
  { {0.923655933587500,0.066803251012200},0.009421666963733},
  { {0.923655933587500,0.009540815400299},0.009421666963733},
  { {0.009540815400299,0.923655933587500},0.009421666963733}
};
*/
void checkCudaError(const char *message)
{
    cudaError_t error = cudaGetLastError();
    if(error!=cudaSuccess) {
        fprintf(stderr,"ERROR: %s: %s\n", message, cudaGetErrorString(error) );
        exit(-1);
    }
}

void read_mesh(FILE *mesh_file, 
              int   *num_elem  , int *num_sides,
              float *V1x, float *V1y,
              float *V2x, float *V2y,
              float *V3x, float *V3y,
              float *sides_x1, float *sides_y1,
              float *sides_x2, float *sides_y2,
              float *sides_x3, float *sides_y3,
              float *elem_s1,  float *elem_s2, float *elem_s3,
              float *left_elem, float *right_elem) {
    printf("inside function.\n");
    int i, j, s1, s2, s3, numsides, n_elem;

    char line[100];
    i = 0;
    numsides = 0;
    while(fgets(line, 100, mesh_file) != NULL) {
        // these three vertices define the element
        printf("i = %i \n", i);
        sscanf(line, "%f %f %f %f %f %f", &V1x[i], &V1y[i], &V2x[i], &V2y[i], &V3x[i], &V3y[i]);

        // determine whether we should add these three sides or not
        s1 = 1;
        s2 = 1;
        s3 = 1;

        // scan through the existing sides to see if we already added it
        // TODO: yeah, there's a better way to do this.
        for (j = 0; j < numsides; j++) {
            //printf("checking bool...\n");
            if ((sides_x1[j] == V1x[i] && sides_y1[j] == V1y[i]
             && sides_x2[j] == V2x[i] && sides_y2[j] == V2y[i]) 
            || (sides_x2[j] == V1x[i] && sides_y2[j] == V1y[i]
             && sides_x1[j] == V2x[i] && sides_y1[j] == V2y[i])) {
                s1 = 0;
                // link this element to that side
                //printf("linking to side\n");
                elem_s1[i] = numsides;
                // and that side to this element either by left or right sided
                // if there's no left element, make this the left element otherwise, 
                // make this a right element 

                // if left element is not set, make this the left element
                if (left_elem[numsides] != -1) {
                    left_elem[numsides] = i; // something like this
                } else if (right_elem[numsides] != -1) {
                    left_elem[numsides] = i; // something like this
                }
            }
            //printf("checking bool...\n");
            if ((sides_x1[j] == V2x[i] && sides_y1[j] == V2y[i]
             && sides_x2[j] == V3x[i] && sides_y2[j] == V3y[i]) 
            || (sides_x2[j] == V2x[i] && sides_y2[j] == V2y[i]
             && sides_x1[j] == V3x[i] && sides_y1[j] == V3y[i])) {
                s2 = 0;
                // link this element to that side
                elem_s2[i] = numsides;
            }
            //printf("checking bool...\n");
            if ((sides_x1[j] == V2x[i] && sides_y1[j] == V2y[i]
             && sides_x2[j] == V3x[i] && sides_y2[j] == V3y[i]) 
            || (sides_x2[j] == V2x[i] && sides_y2[j] == V2y[i]
             && sides_x1[j] == V3x[i] && sides_y1[j] == V3y[i])) {
                s3 = 0;
                // link this element to that side
                elem_s3[i] = numsides;
            }
        }
        //printf("now check s1.\n");
        // if we haven't added the side already, add it
        if (s1) {
            //printf("linking sides\n");
            sides_x1[numsides] = V1x[i];
            sides_y1[numsides] = V1y[i];
            sides_x2[numsides] = V2x[i];
            sides_y2[numsides] = V2y[i];
            
            //printf("linking elem_s1\n");
            // link the added side to this element
            elem_s1[i] = numsides;

            // if left element is not set, make this the left element
            if (left_elem[numsides] != -1) {
                left_elem[numsides] = i;
            } else {
                right_elem[numsides] = i;
            }
            numsides++;
        }
        //printf("now check s2.\n");
        if (s2) {
            sides_x1[numsides] = V2x[i];
            sides_y1[numsides] = V2y[i];
            sides_x2[numsides] = V3x[i];
            sides_y2[numsides] = V3y[i];

            // link the added side to this element
            elem_s2[i] = numsides;

            // if left element is not set, make this the left element
            if (left_elem[numsides] != -1) {
                left_elem[numsides] = i;
            } else {
                right_elem[numsides] = i;
            }
            numsides++;
        }
        //printf("now check s3.\n");
        if (s3) {
            sides_x1[numsides] = V3x[i];
            sides_y1[numsides] = V3y[i];
            sides_x2[numsides] = V1x[i];
            sides_y2[numsides] = V1y[i];

            // link the added side to this element
            elem_s3[i] = numsides;

            // if left element is not set, make this the left element
            if (left_elem[numsides] != -1) {
                left_elem[numsides] = i;
            } else {
                right_elem[numsides] = i;
            }
            numsides++;
        }
        i++;
    }

    *num_sides = numsides;
    *num_elem  = n_elem;
}

void init_gpu(int num_elem, int num_sides, int n_p) {
    checkCudaError("error before init.");
    //cudaDeviceReset();
    //cudaMalloc((void **) &d_something, n * sizeof(float));
    printf("%i\n", num_elem * (n_p + 1));

    //cudaMalloc((void **) &d_c, 100 * sizeof(float));
}

int main() {
    checkCudaError("error before start.");
    int num_elem, num_sides;
    int n_p;
    float *V1x, *V1y, *V2x, *V2y, *V3x, *V3y;

    float *sides_x1, *sides_x2, *sides_x3;
    float *sides_y1, *sides_y2, *sides_y3;

    float *left_elem, *right_elem;
    float *elem_s1, *elem_s2, *elem_s3;

    n_p = 0;

    printf("starting execution.\n");
    FILE *mesh_file;

    // first line should be the number of elements
    fgets(line, 100 ,mesh_file);
    sscanf(line, "%i", &num_elem);

    // allocate vertex points
    V1x = (float *) malloc(num_elem * sizeof(float));
    V1y = (float *) malloc(num_elem * sizeof(float));
    V2x = (float *) malloc(num_elem * sizeof(float));
    V2y = (float *) malloc(num_elem * sizeof(float));
    V3x = (float *) malloc(num_elem * sizeof(float));
    V3y = (float *) malloc(num_elem * sizeof(float));

    elem_s1 = (float *) malloc(num_elem * sizeof(float));
    elem_s2 = (float *) malloc(num_elem * sizeof(float));
    elem_s3 = (float *) malloc(num_elem * sizeof(float));

    // these are too big; should be a way to figure out how many we actually need
    sides_x1 = (float *) malloc(3*num_elem * sizeof(float));
    sides_x2 = (float *) malloc(3*num_elem * sizeof(float));
    sides_x3 = (float *) malloc(3*num_elem * sizeof(float));
    sides_y1 = (float *) malloc(3*num_elem * sizeof(float));
    sides_y2 = (float *) malloc(3*num_elem * sizeof(float));
    sides_y3 = (float *) malloc(3*num_elem * sizeof(float));

    left_elem  = (float *) malloc(num_elem * sizeof(float));
    right_elem = (float *) malloc(num_elem * sizeof(float));

    for (i = 0; i < num_elem; i++) {
        left_elem[i] = -1;
    }

    printf("allocated data inside of the mesh generator successfully.\n");

    mesh_file = fopen(filename, "rt");
    read_mesh(mesh_file, &num_elem, &num_sides,
                                 V1x, V1y, V2x, V2y, V3x, V3y,
                                 sides_x1, sides_y1, 
                                 sides_x2, sides_y2, 
                                 sides_x3, sides_y3, 
                                 elem_s1, elem_s2, elem_s3,
                                 left_elem, right_elem);
    fclose(mesh_file);

    init_gpu(num_elem, num_sides, n_p);

    int i;
    for (i = 0; i < num_elem; i++) {
        printf("%i \n", V2x[i]);
    }
    // free up memory
    //free(V1x);
    //free(V1y);
    //free(V2x);
    //free(V2y);
    //free(V3x);
    //free(V3y);

    //free(sides_x1);
    //free(sides_y1);
    //free(sides_x2);
    //free(sides_y2);
    //free(sides_x3);
    //free(sides_y3);

    //free(elem_s1);
    //free(elem_s2);
    //free(elem_s3);

    //free(left_elem);
    //free(right_elem);

    return 0;
}
