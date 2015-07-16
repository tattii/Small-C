class SmallC::Parse
rule
  target                 : program
                         | /* none */

  program                : external_declaration                 { result = [val[0]] }
                         | program external_declaration         { result.push val[1] }

  external_declaration   : declaration
                         | function_prototype
                         | function_definition

  declaration            : type_specifier declarator_list ';'   { result = Node.new(:decl, {type:val[0][:value], decls:val[1]}, val[0][:pos]) }

  declarator_list        : declarator                           { result = [val[0]] }
                         | declarator_list ',' declarator       { result.push val[2] }

  declarator             : direct_declarator                    { result = Node.new(:declarator, val[0], nil) }
                         | '*' direct_declarator                { result = Node.new(:declarator, ['*', val[1]], nil) }

  direct_declarator      : IDENT                                { result = [val[0][:value]] }
                         | IDENT '[' NUMBER ']'                 { result = [val[0][:value], val[2][:value]] }

  function_prototype     : type_specifier function_declarator ';' { result = Node.new(:function_proto, {type:val[0][:value], decl:val[1]}, val[0][:pos]) }

  function_declarator    : IDENT '(' param_type_list_opt ')'      { result = Node.new(:function_decl, {name:[val[0][:value]], params:val[2]}, val[0][:pos]) }
                         | '*' IDENT '(' param_type_list_opt ')'  { result = Node.new(:function_decl, {name:['*', val[1][:value]], params:val[3]}, val[0][:pos]) }
 
  function_definition    : type_specifier function_declarator compound_statement
                                                                { result = Node.new(:function_def, {type:val[0][:value], decl:val[1], stmts:val[2]}, val[0][:pos]) }

  param_type_list_opt    : /* optional */                       { result = [] }
                         | param_type_list

  param_type_list        : param_declaration                     { result = [val[0]] }
                         | param_type_list ',' param_declaration { result.push val[2] }

  param_declaration      : type_specifier param_declarator      { result = Node.new(:param, {type:val[0][:value], name:val[1]}, val[0][:pos]) }

  param_declarator       : IDENT                                { result = [val[0][:value]] }
                         | '*' IDENT                            { result = ['*', val[1][:value]] }

  type_specifier         : INT                                  { result[:value] = :int }
                         | VOID                                 { result[:value] = :void }

  statement              : ';'                                  { result = Node.new(:skip) }
                         | expression ';'                       { result = Node.new(:expr, [val[0]], nil) } 
                         | compound_statement
                         | IF '(' expression ')' statement      { result = Node.new(:if, {cond:val[2], stmt:val[4], else_stmt:nil}, val[0][:pos]) }
                         | IF '(' expression ')' statement ELSE statement
                                                                { result = Node.new(:if, {cond:val[2], stmt:val[4], else_stmt:val[6]}, val[0][:pos]) }
                         | WHILE '(' expression ')' statement   { result = Node.new(:while, {cond:val[2], stmt:val[4]}, val[0][:pos]) }
                         | FOR '(' expression_opt ';' expression_opt ';' expression_opt ')' statement
                                                                { # for syntax sugar
                                                                  stmt = val[8]
                                                                  iter = val[6]
                                                                  if (stmt.type == :compound_stmt)
                                                                    stmt.attr[:stmts].concat iter
                                                                  else
                                                                    stmt = Node.new(:compound_stmt, {decls:[], stmts:[stmt, iter]}, val[0][:pos])
                                                                  end
                                                                  result = [
                                                                    Node.new(:expr, [val[2]], nil),
                                                                    Node.new(:while, {cond:val[4], stmt:stmt}, val[0][:pos])
                                                                  ]
                                                                }
                         | RETURN expression_opt ';'            { result = Node.new(:return, [val[1]], val[0][:pos]) }

  compound_statement     : '{' declaration_list_opt statement_list_opt '}'
                                                                { result = Node.new(:compound_stmt, {decls:val[1], stmts:val[2]}, val[0][:pos]) }

  declaration_list_opt   : /* optional */                       { result = [] }
                         | declaration_list

  declaration_list       : declaration                          { result = [val[0]] }
                         | declaration_list declaration         { result.push val[1] }

  statement_list_opt     : /* optional */                       { result = [] }
                         | statement_list

  statement_list         : statement                            { result = val[0].is_a?(Array) ? val[0] : [val[0]] }
                         | statement_list statement             { result.push val[1].is_a?(Array) ? val[1].flatten : val[1] }

  expression_opt         : /* optional */                       { result = [] }
                         | expression

  expression             : assign_expr                          { result = [val[0]] }
                         | expression ',' assign_expr           { result.push val[2] }
 
  assign_expr            : logical_or_expr 
                         | logical_or_expr '=' assign_expr      { result = Node.new(:assign, [val[0], val[2]], val[1][:pos]) }

  logical_or_expr        : logical_and_expr 
                         | logical_or_expr '||' logical_and_expr { result = Node.new(:logical_op, ['||', val[0], val[2]], val[1][:pos]) }
 
  logical_and_expr       : equality_expr 
                         | logical_and_expr '&&' equality_expr  { result = Node.new(:logical_op, ['&&', val[0], val[2]], val[1][:pos]) }

  equality_expr          : relational_expr 
                         | equality_expr '==' relational_expr   { result = Node.new(:eq_op, ['==', val[0], val[2]], val[1][:pos]) }
                         | equality_expr '!=' relational_expr   { result = Node.new(:eq_op, ['!=', val[0], val[2]], val[1][:pos]) }

  relational_expr        : add_expr 
                         | relational_expr '<' add_expr         { result = Node.new(:rel_op, ['<', val[0], val[2]], val[1][:pos]) }
                         | relational_expr '>' add_expr         { result = Node.new(:rel_op, ['>', val[0], val[2]], val[1][:pos]) }
                         | relational_expr '<=' add_expr        { result = Node.new(:rel_op, ['<=', val[0], val[2]], val[1][:pos]) }
                         | relational_expr '>=' add_expr        { result = Node.new(:rel_op, ['>=', val[0], val[2]], val[1][:pos]) }

  add_expr               : mult_expr 
                         | add_expr '+' mult_expr               { result = Node.new(:op, ['+', val[0], val[2]], val[1][:pos]) }
                         | add_expr '-' mult_expr               { result = Node.new(:op, ['-', val[0], val[2]], val[1][:pos]) }

  mult_expr              : unary_expr 
                         | mult_expr '*' unary_expr             { result = Node.new(:op, ['*', val[0], val[2]], val[1][:pos]) }
                         | mult_expr '/' unary_expr             { result = Node.new(:op, ['/', val[0], val[2]], val[1][:pos]) }

  unary_expr             : postfix_expr 
                         | '-' unary_expr                       { result = Node.new(:op, ['-', 0, val[1]], val[0][:pos]) }
                         | '&' unary_expr                       { # for syntax sugar
                                                                  if val[1].type == :pointer
                                                                    result = val[1].attr[0]
                                                                  else
                                                                    result = Node.new(:address, [val[1]], val[0][:pos])
                                                                  end
                                                                }
                         | '*' unary_expr                       { result = Node.new(:pointer, [val[1]], val[0][:pos]) }

  postfix_expr           : primary_expr                         { result = val[0] } 
                         | postfix_expr '[' expression ']'      { result = Node.new(:pointer, [Node.new(:op, ['+', val[0], Node.new(:expr, [val[2]], val[1][:pos])], nil)], val[0].pos) }
                         | IDENT '(' argument_expr_list_opt ')' { result = Node.new(:call, {name:val[0][:value], args:val[2]}, val[0][:pos]) }

  primary_expr           : IDENT                                { result = Node.new(:variable, {name:val[0][:value]}, val[0][:pos]) }
                         | NUMBER                               { result = Node.new(:number, {value:val[0][:value]}, val[0][:pos]) }
                         | '(' expression ')'                   { result = Node.new(:expr, [val[1]], val[0][:pos]) }

  argument_expr_list_opt : /* optional */                       { result = [] }
                         | argument_expr_list

  argument_expr_list     : assign_expr                          { result = [val[0]] }
                         | argument_expr_list ',' assign_expr   { result.push val[2] }


end
