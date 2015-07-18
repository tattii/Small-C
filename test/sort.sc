#include "small-c.c"

int data[8];

void sort(){
	int i, j, tmp;
	for (i = 7; i >= 0; i = i-1){
		for (j = 0; j < i; j = j+1){
			if (data[j] > data[i]){
				tmp = data[j];
				data[j] = data[i];
				data[i] = tmp;
			}
		}
	}
}

void output(){
	int i;
	for (i = 0; i < 8; i = i+1){
		print(data[i]);
	}
}

void main(){
	data[0] = 4;
	data[1] = 2;
	data[2] = 7;
	data[3] = 6;
	data[4] = 0;
	data[5] = 1;
	data[6] = 3;
	data[7] = 5;

	sort();
	output();
}
