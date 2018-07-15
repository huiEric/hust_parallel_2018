// ��� CUDA ��
#include "cuda_runtime.h"
#include "cuda.h"
#include "device_launch_parameters.h"

#include <cstdlib>
#include<opencv2/opencv.hpp>
#include <time.h>
#include<iostream>

#define PARTS 4

using namespace cv;
using namespace std;

typedef struct st_range {
	int x1;
	int y1;
	int x2;
	int y2;
}StRange;

Mat srcImage, grayImage, binarygray;

const int N = 100;
const int BLOCK_data = 1;	// ����
const int THREAD_data = 4;	// �����е��߳���

static void * g_binary(void *range)		//��ֵ��
{
	StRange rg = *(StRange *)range;
	binarygray = Mat::zeros(grayImage.rows, grayImage.cols, grayImage.type());
	for (int i = rg.x1; i < rg.x2; i++)
	{
		for (int j = rg.y1; j < rg.y2; j++)
		{
			if (grayImage.data[i*grayImage.step + j] > 128)
			{
				binarygray.data[i*binarygray.step + j] = 255;		//white
			}
			else
			{
				binarygray.data[i*binarygray.step + j] = 0;			//black
			}
		}
	}
	return NULL;
}
// �˺����������˵��ã��豸��ִ�С�
__global__ static void g_dilation(unsigned char *imgData, unsigned char *result, int rows, int cols)  //��ʴ
{
	StRange srcRange, rg, ranges[PARTS];
	srcRange = { 0, 0, rows, cols };
	//�з�ͼ��
	ranges[0] = { 0, 0, srcRange.x2 / 4, srcRange.y2 };
	ranges[1] = { srcRange.x2 / 4, 0, srcRange.x2 / 2, srcRange.y2 };
	ranges[2] = { srcRange.x2 / 2 ,0 , 3 * srcRange.x2 / 4, srcRange.y2 };
	ranges[3] = { 3 * srcRange.x2 / 4, 0 , srcRange.x2, srcRange.y2 };
	for (int tid = 0; tid < 4; tid++)
	{
		if (tid == threadIdx.x)
		{
			//printf("thid:%d\n", tid);
			rg = ranges[tid];
			//printf("x1: %d, y1: %d\nx2: %d, y2:%d\n", ranges[tid].x1, ranges[tid].y1, ranges[tid].x2, ranges[tid].y2);
			for (int i = rg.x1; i < rg.x2; i++)
			{
				for (int j = rg.y1; j < rg.y2; j++)
				{
					if (imgData[(i - 1)*cols + j] + imgData[(i - 1)*cols + j + 1] + imgData[i*cols + j + 1] == 0)
					{
						result[i*cols + j] = 0;
					}
					else
					{
						result[i*cols + j] = 255;
					}
				}
			}
			//printf("Over thread%d\n\n", tid);
		}
	}
}
__global__ static void g_erosion(unsigned char *imgData, unsigned char *result, int rows, int cols)  //����
{
	StRange srcRange, rg, ranges[PARTS];
	srcRange = { 0, 0, rows, cols };
	//�з�ͼ��
	ranges[0] = { 0, 0, srcRange.x2 / 4, srcRange.y2 };
	ranges[1] = { srcRange.x2 / 4, 0, srcRange.x2 / 2, srcRange.y2 };
	ranges[2] = { srcRange.x2 / 2 ,0 , 3 * srcRange.x2 / 4, srcRange.y2 };
	ranges[3] = { 3 * srcRange.x2 / 4, 0 , srcRange.x2, srcRange.y2 };
	for (int tid = 0; tid < 4; tid++)
	{
		if (tid == threadIdx.x)
		{
			printf("thid:%d\n", tid);
			rg = ranges[tid];
			//printf("x1: %d, y1: %d\nx2: %d, y2:%d\n", ranges[tid].x1, ranges[tid].y1, ranges[tid].x2, ranges[tid].y2);
			for (int i = rg.x1; i < rg.x2; i++)
			{
				for (int j = rg.y1; j < rg.y2; j++)
				{
					if (imgData[(i - 1)*cols + j] == 0 || imgData[(i - 1)*cols + j - 1] == 0 || imgData[i*cols + j + 1] == 0)
					{
						result[i*cols + j] = 0;
					}
					else
					{
						result[i*cols + j] = 255;
					}
				}
			}
			printf("Over thread%d\n\n", tid);
		}
	}
}
// CUDA��ʼ������
bool InitCUDA()
{
	int deviceCount;
	cudaGetDeviceCount(&deviceCount);	// ��ȡ��ʾ�豸��
	if (deviceCount == 0)
	{
		cout << "�Ҳ����豸" << endl;
		return EXIT_FAILURE;
	}
	int i;
	for (i = 0; i<deviceCount; i++)
	{
		cudaDeviceProp prop;
		if (cudaGetDeviceProperties(&prop, i) == cudaSuccess) // ��ȡ�豸����
		{
			if (prop.major >= 1) //cuda��������
			{
				break;
			}
		}
	}
	if (i == deviceCount)
	{
		cout << "�Ҳ���֧�� CUDA ������豸" << endl;
		return EXIT_FAILURE;
	}
	cudaSetDevice(i); // ѡ��ʹ�õ���ʾ�豸
	return EXIT_SUCCESS;
}

int main()
{
	if (InitCUDA()) // ��ʼ�� CUDA ���뻷��
		return EXIT_FAILURE;
	cout << "�ɹ����� CUDA ���㻷��" << endl << endl;

	clock_t begin, end;
	double cost;
	cout << "\n\n�������漰����" << "��ʴ��erosion�������ͣ�dilation)��\n\n";
	
	system("color 3f");
	srcImage = imread("D://2.jpg");
	imshow("ԭͼ", srcImage);
	cvtColor(srcImage, grayImage, CV_RGB2GRAY);		//RGBͼ��ת��Ϊ�Ҷ�ͼ
	StRange srcRange = { 0, 0, srcImage.rows, srcImage.cols };
	g_binary(&srcRange);		//�Ҷ�ͼ��ֵ������
	imshow("binarygray", binarygray);

	// ���ݲ���
	unsigned char *img, *result1, *result2;
	int arraySize = sizeof(unsigned char)*srcImage.cols * srcImage.rows;

	//��ʼ��¼
	begin = clock();
	// ���Դ���Ϊ������󿪱ٿռ�
	cudaMalloc((void**)&img, arraySize);
	// ���Դ���Ϊ������󿪱ٿռ�
	cudaMalloc((void**)&result1, arraySize);
	cudaMalloc((void**)&result2, arraySize);

	// �����ݴ�����Դ�
	cudaMemcpy(img, binarygray.data, arraySize, cudaMemcpyHostToDevice);

	// ���� kernel ���� - �˺������Ը����Դ��ַ�Լ�����Ŀ�ţ��̺߳Ŵ������ݡ�
	g_erosion << <BLOCK_data, THREAD_data, 0 >> > (img, result1, srcImage.rows, srcImage.cols);
	g_dilation << <BLOCK_data, THREAD_data, 0 >> > (img, result2, srcImage.rows, srcImage.cols);
	// ���ڴ���Ϊ������󿪱ٿռ�
	unsigned char * resData1 = new unsigned char[srcImage.rows * srcImage.cols];
	unsigned char * resData2 = new unsigned char[srcImage.rows * srcImage.cols];
	// ���Դ��ȡ����Ľ��
	cudaMemcpy(resData1, result1, arraySize, cudaMemcpyDeviceToHost);
	cudaMemcpy(resData2, result2, arraySize, cudaMemcpyDeviceToHost);

	Mat erosion(srcImage.rows, srcImage.cols, CV_8UC1, resData1);
	Mat dilation(srcImage.rows, srcImage.cols, CV_8UC1, resData2);
	imshow("dilation", dilation);
	imshow("erosion", erosion);

	// �ͷ��Դ�
	cudaFree(img);
	cudaFree(result1);
	cudaFree(result2);

	end = clock();
	cost = (double)(end - begin);
	printf("Time cost is: %lf ms", cost);
	waitKey(0);
	return 0;
}