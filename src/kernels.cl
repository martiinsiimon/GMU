/*
 * Accelerated k-means and mean-shift algorithms via OpenCL
 * Authors: Martin Simon & Pavel Sirucek
 *
 * OpenCL kernels
 */


__kernel void k_means()
{
}

__kernel void mean_shift(__global uchar4* input, __global uint* peaks, __global uint* counts,
__local float* cache, uint width, uint height, uint winsize, float maxlength)
{
int x = get_global_id(0);
int y = get_global_id(1);


//reconstruct window by given param
float actx = convert_float(x);
float acty = convert_float(y);
int wymax = acty + ((winsize-1) / 2) + 1;
int wymin = acty - ((winsize-1) / 2);
int wxmax = actx + ((winsize-1) / 2) + 1;
int wxmin = actx - ((winsize-1) / 2);

float oldx = convert_float(x);
float oldy = convert_float(y);

//cycle control value
bool cont = true;
int iter = 0;
//mean structures
float newX, newY;

//begincycle - until the step is bigger than relevant
do {
    newX = newY = 0;
    for (int wy = wymin; wy < wymax; wy++)
    {
        for (int wx = wxmin; wx < wxmax; wx++)
        {
            if (wx < 0 || wy < 0 || wx > width-1|| wy > height-1)
            {
                //out of original window
                //set 0 to the position of the x in local cache
                continue;
            }
            else if (wx == convert_int(actx) && wy == convert_int(acty))
            {
                //set 1 to the position of the x
                //to [actx-wxmin,acty-wymin] set 1

                newX += (wx - actx);
                newY += (wy - acty);
            }
            else
            {
                //compute lengths for [wx,wy] - [x,y]
                //if the length is bigger the maxlength, set 0 there
                //otherwise set the length
                int gid = convert_int_rte(actx) + convert_int_rte(acty)*width;
                float length = 1/sqrt(convert_float(
                    (actx-wx)*(actx-wx) +
                    (acty-wy)*(acty-wy) +
                    (input[gid].s0 - input[wx + wy*width].s0)*(input[gid].s0 - input[wx + wy*width].s0) +
                    (input[gid].s1 - input[wx + wy*width].s1)*(input[gid].s1 - input[wx + wy*width].s1) +
                    (input[gid].s2 - input[wx + wy*width].s2)*(input[gid].s2 - input[wx + wy*width].s2)));

                newX += (wx - actx) * length;
                newY += (wy - acty) * length;
            }
        }
    }
//printf("[%d:%d]- old:[%f,%f], new diff:[%f,%f]\n", x,y,actx,acty,newX,newY);
    //recompute mean of the window
    oldx = actx;
    oldy = acty;

    actx = actx + newX;
    acty = acty + newY;



    //shift the window to the mean be in the center
    wymax = convert_int_rte(acty) + ((winsize-1) / 2) + 1;
    wymin = convert_int_rte(acty) - ((winsize-1) / 2);
    wxmax = convert_int_rte(actx) + ((winsize-1) / 2) + 1;
    wxmin = convert_int_rte(actx) - ((winsize-1) / 2);

    if((newX < 0 ? -1*newX : newX) <= 0.2 && (newY < 0 ? -1*newY : newY) <= 0.2)
    {
        //the step is lower the 0.5pix
        cont = false;
    }


    //endcycle
    iter++;
} while (cont);

actx = convert_float(max(convert_int_rte(actx),0));
acty = convert_float(max(convert_int_rte(acty),0));

actx = convert_float(min(convert_int_rte(actx),convert_int_rte(width)-1));
acty = convert_float(min(convert_int_rte(acty),convert_int_rte(height)-1));

printf("[%d,%d]/%d reached: [%d, %d]\n",x,y,iter,convert_int_rte(actx),convert_int_rte(acty));

//store the peak position to peaks array
peaks[x+y*width] = convert_int_rte(actx) + convert_int_rte(acty)*width;

//increment value on peak position in counts array
counts[convert_int_rte(actx) + convert_int_rte(acty)*width] = counts[convert_int_rte(actx) + convert_int_rte(acty)*width] + 1;

}

__kernel void mean_shift_peaks(__global uint* peaks, uint width, uint height)
{
    int x = get_global_id(0);
	int y = get_global_id(1);

//    if (x < 0 || y < 0 || x >= width || y >= height)
//    {
//        return;
//    }

    printf("[%d,%d]\n",x,y);

    int gid = x + width*y;
    int peak = peaks[gid];
    int i = 0;

    while (peaks[peaks[peak]] != peaks[peak] && i < 10)
    {
        i++;
        peaks[gid] = peaks[peak];
        peak = peaks[peaks[peak]];
    }
}

__kernel void mean_shift_result(__global uint* counts, __global uint* peaks, __global uchar4* output, uint width, uint height)
{
	int x = get_global_id(0);
	int y = get_global_id(1);

	if(x < width && y < height)
	{
		int gid = x + y*width;
//printf(peaks[gid]);
		//output[gid] = add_sat(sobel_x[gid], sobel_y[gid]);
        //if(peaks[gid] != 0)
        //    output[gid].s0 = 255;
        //else
        output[gid].s0 = 255-peaks[gid];
        output[gid].s1 = 255-peaks[gid];
        output[gid].s2 = 255-peaks[gid];

        output[gid].s3 = 255;
    }
}

//TODO delete following

__kernel void edge_x( __global uchar4* input, __global uchar4* output, uint width, uint height, __local float4* cache)
{
	int x = get_global_id(0); //defines column
	int y = get_global_id(1); //defines row

	int lx = get_local_id(0);
	int lw = get_local_size(0);

	if(lx == 0)
	{
		int startI = y*width;
		int endI = y*width + height - 1;
		output[startI] = (uchar4)(0, 0, 0, 0);
		output[endI] = (uchar4)(0, 0, 0, 0);
	}

	int kw = 0;
	while(kw < width)
	{
		int gindex = y*width + lx + kw;

		//cache in the row
		if(lx + kw < width)
		{
			cache[lx] = convert_float4(input[gindex]);
		}

		barrier(CLK_LOCAL_MEM_FENCE);

		if(lx + kw < width-1 && lx > 0 && lx < lw - 1)
		{
			output[gindex] = convert_uchar4(fabs(cache[lx - 1] - cache[lx + 1]));
		}

		kw += lw - 1;
	}
}

__kernel void edge_y( __global uchar4* input, __global uchar4* output, uint width, uint height, __local float4* cache)
{
	int x = get_global_id(0); //defines column
	int y = get_global_id(1); //defines row

	int ly = get_local_id(1);
	int lh = get_local_size(1);

	if(ly == 0)
	{
		int startI = x;
		int endI = (height-1)*width + x;
		output[startI] = (uchar4)(0, 0, 0, 0);
		output[endI] = (uchar4)(0, 0, 0, 0);
	}

	int kh = 0;
	while(kh < height)
	{
		int gindex = (ly + kh)*width + x;

		//cache in the column
		if(ly + kh < height)
		{
			cache[ly] = convert_float4(input[gindex]);
		}

		barrier(CLK_LOCAL_MEM_FENCE);

		if(ly + kh < height-1 && ly > 0 && ly < lh - 1)
		{
			output[gindex] = convert_uchar4_sat_rte(fabs(cache[ly - 1] - cache[ly + 1]));
		}

		kh += lh - 1;
	}
}


__kernel void edge_result(__global uchar4* sobel_x, __global uchar4* sobel_y, __global uchar4* output, uint width, uint height)
{
	int x = get_global_id(0);
	int y = get_global_id(1);

	if(x < width && y < height)
	{
		int gid = x + y*width;
		output[gid] = add_sat(sobel_x[gid], sobel_y[gid]);
		output[gid].s3 = 255;
	}
}
