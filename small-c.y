class SmallC
rule
  target: program
        | /* none */

  program                : external_declaration                      { result = [:program, val[0]] }
                         | program external_declaration              { result.push val[1] }

  external_declaration   : declaration
                         | function_prototype
                         | function_definition

  declaration            : type_specifier declarator_list ';'        { result = [:declaration, val[0], val[1]] }

  declarator_list        : declarator                                { result = [:declarator_list, val[0]] }
                         | declarator_list ',' declarator            { result.push val[2] }

  declarator             : direct_declarator                         { result = [:declarator, val[0]] }
                         | '*' direct_declarator                     { result = [:p_declarator, val[1]] }

  direct_declarator      : IDENT                  
                         | IDENT '[' constant ']'                    { result = [:array_declarator, val[0], val[2]] }

  function_prototype     : type_specifier function_declarator ';'    { result = [:prototype, val[0], val[1]] }

  function_declarator    : IDENT '(' parameter_type_list_opt ')'     { result = [:function_declare, val[0], val[2]] }
                         | '*' IDENT '(' parameter_type_list_opt ')' { result = [:p_function_declare, val[1], val[3]] }
 
  function_definition    : type_specifier function_declarator compound_statement
                                                                     { result = [:function, val[0], val[1], val[2]] }

  parameter_type_list_opt: /* optional */
                         | parameter_type_list

  parameter_type_list    : parameter_declaration                     { result = [:param_list, val[0]] }
                         | parameter_type_list ',' parameter_declaration { result.push val[2] }

  parameter_declaration  : type_specifier parameter_declarator       { result = [:param, val[0], val[1]] }

  parameter_declarator   : IDENT
                         | '*' IDENT { result = [:p_param, val[1]] }

  type_specifier         : INT
                         | VOID

  statement              : ';'                                       { result = [:skip] }
                         | expression ';'                            { result = val[0] }
                         | compound_statement
                         | IF '(' expression ')' statement           { result = [:if, val[2], val[4]] }
                         | IF '(' expression ')' statement ELSE statement
                                                                     { result = [:if, val[2], val[4], val[6]] }
                         | WHILE '(' expression ')' statement        { result = Node.new(:while, {cond:val[2], stmt:val[4]}, val[0][:pos])}
                         | FOR '(' expression_opt ';' expression_opt ';' expression_opt ')' statement
                                                                     { result = [:for, val[2], val[4], val[6], val[8]]}
                         | RETURN expression_opt ';'                 { result = [:return, val[1]] }

  compound_statement     : '{' declaration_list_opt statement_list_opt '}'
                                                                     { result = [:block, val[1], val[2]] }

  declaration_list_opt   : /* optional */
                         | declaration_list

  declaration_list       : declaration                                { result = [:declaration_list, val[0]] }
                         | declaration_list declaration               { result.push val[1] }

  statement_list_opt     : /* optional */
                         | statement_list

  statement_list         : statement                                 { result = [:stmt_list, val[0]] }
                         | statement_list statement                  { result.push val[1] }

  expression_opt         : /* optional */
                         | expression

  expression             : assign_expr                               { result = [:expr, val[0]] }
                         | expression ',' assign_expr                { result.push val[2] }
 
  assign_expr            : logical_or_expr 
                         | logical_or_expr '=' assign_expr           { result = [:assign, val[0], val[2]] }

  logical_or_expr        : logical_and_expr 
                         | logical_or_expr '||' logical_and_expr     { result = [:or, val[0], val[2]] }
 
  logical_and_expr       : equality_expr 
                         | logical_and_expr '&&' equality_expr       { result = [:and, val[0], val[2]] }

  equality_expr          : relational_expr 
                         | equality_expr '==' relational_expr        { result = [:eq, val[0], val[2]] }
                         | equality_expr '!=' relational_expr        { result = [:ne, val[0], val[2]] }

  relational_expr        : add_expr 
                         | relational_expr '<' add_expr              { result = [:lt, val[0], val[2]] }
                         | relational_expr '>' add_expr              { result = [:gt, val[0], val[2]] }
                         | relational_expr '<=' add_expr             { result = [:le, val[0], val[2]] }
                         | relational_expr '>=' add_expr             { result = [:ge, val[0], val[2]] }

  add_expr               : mult_expr 
                         | add_expr '+' mult_expr                    { result = [:add, val[0], val[2]] }
                         | add_expr '-' mult_expr                    { result = [:sub, val[0], val[2]] }

  mult_expr              : unary_expr 
                         | mult_expr '*' unary_expr                  { result = [:mul, val[0], val[2]] }
                         | mult_expr '/' unary_expr                  { result = [:div, val[0], val[2]] }

  unary_expr             : postfix_expr 
                         | '-' unary_expr                            { result = [:minus,   val[1]] }
                         | '&' unary_expr                            { result = [:address, val[1]] }
                         | '*' unary_expr                            { result = [:pointer, val[1]] }

  postfix_expr           : primary_expr 
                         | postfix_expr '[' expression ']'           { result = [:array, val[2]] }
                         | IDENT '(' argument_expr_list_opt ')'      { reuslt = [:call, val[0], val[2]] }

  primary_expr           : IDENT
                         | NUMBER
                         | '(' expression ')'                        { result = val[1] }

  argument_expr_list_opt : /* optional */
                         | argument_expr_list

  argument_expr_list     : assign_expr                               { result = [:arg, val[0]] }
                         | argument_expr_list ',' assign_expr        { result.push val[2] }


end
