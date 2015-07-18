#
# Small-C Compiler repl
#
require_relative "small-c.rb"

while true
  puts
  print '? '
  str = gets.chop!
  break if /^q$/i =~ str
  SmallC::compile_debug(str)
end
