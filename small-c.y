class SmallC
rule
  target: program
        | /* none */

  program                : external_declaration                 { result = [:program, val[0]] }
                         | program external_declaration         { result.push val[1] }

  external_declaration   : declaration
                         | function_prototype
                         | function_definition

  declaration            : type_specifier declarator_list ';'   { result = Node.new(:declaration, {type:val[0][:value], decls:val[1]}, val[0][:pos]) }

  declarator_list        : declarator                           { result = [:declarator_list, val[0]] }
                         | declarator_list ',' declarator       { result.push val[2] }

  declarator             : direct_declarator                    { result = Node.new(:declarator, {declarator:val[0]}) }
                         | '*' direct_declarator                { result = Node.new(:p_declarator, {declarator:val[1]}) }

  direct_declarator      : IDENT                                { result = Node.new(:variable_declarator, {name:val[0][:value]}, val[0][:pos])}
                         | IDENT '[' NUMBER ']'                 { result = Node.new(:array_declarator, {name:val[0][:value], length:val[2][:value]}, val[0][:pos]) }

  function_prototype     : type_specifier function_declarator ';'    { result = Node.new(:prototype, {type:val[0], decl:val[1]}, val[0][:pos]) }

  function_declarator    : IDENT '(' parameter_type_list_opt ')'     { result = Node.new(:function_declare, {name:val[0][:value], params:val[2]}, val[0][:pos]) }
                         | '*' IDENT '(' parameter_type_list_opt ')' { result = Node.new(:p_function_declare, {name:val[1][:value], params:val[3]}, val[0][:pos]) }
 
  function_definition    : type_specifier function_declarator compound_statement
                                                                { result = Node.new(:function_def, {type:val[0], name:val[1], stmts:val[2]}, val[0][:pos]) }

  parameter_type_list_opt: /* optional */
                         | parameter_type_list

  parameter_type_list    : parameter_declaration                { result = [:param_list, val[0]] }
                         | parameter_type_list ',' parameter_declaration { result.push val[2] }

  parameter_declaration  : type_specifier parameter_declarator  { result = Node.new(:param, {type:val[0][:value], name:val[1]}, val[0][:pos]) }

  parameter_declarator   : IDENT                                { result = Node.new(:param_name, {name:val[0][:value]}, val[0][:pos]) }
                         | '*' IDENT                            { result = Node.new(:p_param_name, {name:val[1][:value]}, val[0][:pos]) }

  type_specifier         : INT
                         | VOID

  statement              : ';'                                  { result = Node.new(:skip) }
                         | expression ';'
                         | compound_statement
                         | IF '(' expression ')' statement      { result = Node.new(:if, {cond:val[2], stmt:val[4]}, val[0][:pos]) }
                         | IF '(' expression ')' statement ELSE statement
                                                                { result = Node.new(:if, {cond:val[2], stmt:val[4], else_stmt:val[6]}, val[0][:pos]) }
                         | WHILE '(' expression ')' statement   { result = Node.new(:while, {cond:val[2], stmt:val[4]}, val[0][:pos]) }
                         | FOR '(' expression_opt ';' expression_opt ';' expression_opt ')' statement
                                                                { result = Node.new(:for, {init:val[2], cond:val[4], iter:val[6], stmt:val[8]}, val[0][:pos]) }
                         | RETURN expression_opt ';'            { result = Node.new(:return, {expr:val[1]}, val[0][:pos]) }

  compound_statement     : '{' declaration_list_opt statement_list_opt '}'
                                                                { result = Node.new(:compound_stmt, {decls:val[1], stmts:val[2]}, val[0][:pos]) }

  declaration_list_opt   : /* optional */
                         | declaration_list

  declaration_list       : declaration                          { result = [:declaration_list, val[0]] }
                         | declaration_list declaration         { result.push val[1] }

  statement_list_opt     : /* optional */
                         | statement_list

  statement_list         : statement                            { result = [:stmt_list, val[0]] }
                         | statement_list statement             { result.push val[1] }

  expression_opt         : /* optional */
                         | expression

  expression             : assign_expr                          { result = [:expr, val[0]] }
                         | expression ',' assign_expr           { result.push val[2] }
 
  assign_expr            : logical_or_expr 
                         | logical_or_expr '=' assign_expr      { result = Node.new(:assign, {left:val[0], right:val[2]}, val[1][:pos]) }

  logical_or_expr        : logical_and_expr 
                         | logical_or_expr '||' logical_and_expr { result = Node.new(:or, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
 
  logical_and_expr       : equality_expr 
                         | logical_and_expr '&&' equality_expr  { result = Node.new(:and, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }

  equality_expr          : relational_expr 
                         | equality_expr '==' relational_expr   { result = Node.new(:eq, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | equality_expr '!=' relational_expr   { result = Node.new(:ne, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }

  relational_expr        : add_expr 
                         | relational_expr '<' add_expr         { result = Node.new(:lt, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | relational_expr '>' add_expr         { result = Node.new(:gt, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | relational_expr '<=' add_expr        { result = Node.new(:le, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | relational_expr '>=' add_expr        { result = Node.new(:ge, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }

  add_expr               : mult_expr 
                         | add_expr '+' mult_expr               { result = Node.new(:add, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | add_expr '-' mult_expr               { result = Node.new(:sub, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }

  mult_expr              : unary_expr 
                         | mult_expr '*' unary_expr             { result = Node.new(:mul, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }
                         | mult_expr '/' unary_expr             { result = Node.new(:div, {arg1:val[0], arg2:val[2]}, val[1][:pos]) }

  unary_expr             : postfix_expr 
                         | '-' unary_expr                       { result = Node.new(:minus,   {arg:val[1]}, val[0][:pos]) }
                         | '&' unary_expr                       { result = Node.new(:address, {arg:val[1]}, val[0][:pos]) }
                         | '*' unary_expr                       { result = Node.new(:pointer, {arg:val[1]}, val[0][:pos]) }

  postfix_expr           : primary_expr 
                         | postfix_expr '[' expression ']'      { result = Node.new(:array, {index:val[2]}, val[0][:pos]) }
                         | IDENT '(' argument_expr_list_opt ')' { reuslt = Node.new(:call, {name:val[0][:value], args:val[2]}, val[0][:pos]) }

  primary_expr           : IDENT                                { result = Node.new(:variable, {name:val[0][:value]}, val[0][:pos]) }
                         | NUMBER                               { result = Node.new(:number, {value:val[0][:value]}, val[0][:pos]) }
                         | '(' expression ')'                   { result = val[1] }

  argument_expr_list_opt : /* optional */
                         | argument_expr_list

  argument_expr_list     : assign_expr                          { result = [:args, val[0]] }
                         | argument_expr_list ',' assign_expr   { result.push val[2] }


end
