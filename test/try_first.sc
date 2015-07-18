void main() {
  int x;
  int y;

  x = 123;
  y = 456;

  print(x == 123);
  print(x != 123);
  print(x == y);
  print(x != y);

  print(x == 123 && x != y);
  print((x == 123 && x == y) == 0);
  print((x != 123 && x != y) == 0);
}
