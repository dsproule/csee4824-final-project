#include "tj_malloc.h"

#define N 2

void bubble(int arr[], int size) {

    for(int i = 0; i < (size-1); i++)
        for(int j = i+1; j< size; j++)
            if(arr[j] < arr[i]){
                int temp = arr[j];
                arr[j] = arr[i];
                arr[i] = temp;
            }
}

int main()
{
    // int *num_ptr = tj_malloc(sizeof(int));
    int arr[N] = {3, 2};

    bubble(arr, N);

    return 0;
}