/* Mock parser: exists so that PRs touching parsing/parser.mly trigger the
   document-syntax.yml checklist comment, as in oxcaml. */

%token EOF

%start <unit> main

%%

main:
| EOF { () }
