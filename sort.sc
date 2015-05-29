#include "small-c.c"

int data[8] = {4, 2, 7, 6, 0, 1, 3, 5};

void sort(){
	int i, j, tmp;
	for (i = 7; i >= 0; i--){
		for (j = 0; j < i; j++){
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
	for (i = 0; i < 8; i++){
		print(data[i]);
	}
}

void main(){
	sort();
	output();
}
