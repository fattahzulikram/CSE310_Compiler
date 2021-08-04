%option noyywrap 

%x STRING
%x BACKSLASH
%x COMMENT
%x MULTICOMMENT


%{
#include<iostream>
#include<string>
#include<cstring>
#include "S1705058_SymbolInfo.h"
#include "y.tab.h"

extern YYSTYPE yylval;
extern FILE* ErrorFile;

int LineCount = 1;
int LineStart = 1;
int ErrorCount = 0;

%}

WHITESPACE [ \t\v\f\r]+
ALPHANUMERIC [a-zA-Z_]
DIGIT [0-9]
NEWLINE \n
ADDOP [+-] 
MULOP [*/%]

%%
{NEWLINE}	{LineCount++;}

\" 			{BEGIN STRING; LineStart = LineCount;}
<BACKSLASH>\n	{
				LineCount++;
				BEGIN STRING;
			}
<BACKSLASH>t	|
<BACKSLASH>n	|
<BACKSLASH>a	|
<BACKSLASH>b	|
<BACKSLASH>f	|
<BACKSLASH>v	|
<BACKSLASH>\\	|
<BACKSLASH>r	|
<BACKSLASH>\'	|
<BACKSLASH>\"	|
<BACKSLASH>.	{BEGIN STRING;}

<STRING>[\\]	{BEGIN BACKSLASH;}

<STRING>\n	{
				fprintf(ErrorFile, "Error at line %d: Unterminated string\n\n", LineStart);
				ErrorCount++;
				LineCount++;
				BEGIN INITIAL;
			}
<STRING>\"	{BEGIN INITIAL;}

<STRING>[^\"]	{}

"if" {return IF;}
"else" {return ELSE;}
"for" {return FOR;}
"while" {return WHILE;}
"int" {return INT;}
"float" {return FLOAT;}
"double" {return DOUBLE;}
"char" {return CHAR;}
"return" {return RETURN;}
"void" {return VOID;}
"do"	{return DO;}
"break"	{return BREAK;}
"switch"	{return SWITCH;}
"case"	{return CASE;}
"default"	{return DEFAULT;}
"continue"	{return CONTINUE;}
"println" {return PRINTLN;}

{ADDOP} { 
			SymbolInfo *s= new  SymbolInfo(yytext, "ADDOP");
			yylval.Symbol = s;
			return ADDOP;
		}



{MULOP}	{
			SymbolInfo *s= new  SymbolInfo(yytext, "MULOP");
			yylval.Symbol = s;
			return MULOP;
		}
		
"++"	{return INCOP;}
"--"	{return DECOP;}

">" |
"<" |
">=" |
"<=" |
"==" |
"!=" {
		SymbolInfo *s= new  SymbolInfo(yytext, "RELOP");
		yylval.Symbol = s;
		return RELOP;
}

"=" 	{return ASSIGNOP;}

"&&"	|
"||"	{
			SymbolInfo *s= new  SymbolInfo(yytext, "LOGICOP");
			yylval.Symbol = s;
			return LOGICOP;
		}
		
"!"		{return NOT;}
";" 	{return SEMICOLON;}
"," 	{return COMMA;}
"(" 	{return LPAREN;}
")" 	{return RPAREN;}
"{" 	{return LCURL;}
"}" 	{return RCURL;}
"[" 	{return LTHIRD;}
"]" 	{return RTHIRD;}

{DIGIT}+	{
				SymbolInfo *s= new  SymbolInfo(yytext, "CONST_INT");
				yylval.Symbol = s;
				return CONST_INT;
}

{DIGIT}*"."{DIGIT}*	{
	SymbolInfo *s= new  SymbolInfo(yytext, "CONST_FLOAT");
	yylval.Symbol = s;
	return CONST_FLOAT;
}

{DIGIT}*\.{DIGIT}*(\.{DIGIT}*)+	{
				fprintf(ErrorFile, "Error at line %d: Too many decimal points\n\n", LineCount);
				ErrorCount++;
			}
{DIGIT}*(\.)?{DIGIT}*"E"{DIGIT}+	|
{DIGIT}*(\.)?{DIGIT}*"e"{DIGIT}+	|
{DIGIT}*(\.)?{DIGIT}*"E-"{DIGIT}+	|
{DIGIT}*(\.)?{DIGIT}*"e-"{DIGIT}+	|
{DIGIT}*(\.)?{DIGIT}*"E+"{DIGIT}+	|
{DIGIT}*(\.)?{DIGIT}*"e+"{DIGIT}+	{
	SymbolInfo *s= new  SymbolInfo(yytext, "CONST_FLOAT");
	yylval.Symbol = s;
	return CONST_FLOAT;
}
			
{DIGIT}*(\.)?{DIGIT}*"E"{DIGIT}*(\.{DIGIT}*)+	|
{DIGIT}*(\.)?{DIGIT}*"e"{DIGIT}*(\.{DIGIT}*)+	|
{DIGIT}*(\.)?{DIGIT}*"E-"{DIGIT}*(\.{DIGIT}*)+	|
{DIGIT}*(\.)?{DIGIT}*"e-"{DIGIT}*(\.{DIGIT}*)+	|
{DIGIT}*(\.)?{DIGIT}*"E+"{DIGIT}*(\.{DIGIT}*)+	|
{DIGIT}*(\.)?{DIGIT}*"e+"{DIGIT}*(\.{DIGIT}*)+	{
				fprintf(ErrorFile, "Error at line %d: Ill formed number\n\n", LineCount);
				ErrorCount++;
			}
{DIGIT}+{ALPHANUMERIC}+({DIGIT}*{ALPHANUMERIC}*)*	{
				fprintf(ErrorFile, "Error at line %d: Invalid prefix on ID or invalid suffix on Number\n\n", LineCount);
				ErrorCount++;
			}
''			{	//Character Literals Below
				fprintf(ErrorFile, "Error at line %d: Empty character constant error\n\n", LineCount);
				ErrorCount++;
			}
'[^\'\n]*	{
				fprintf(ErrorFile, "Error at line %d: Unterminated Character\n\n", LineCount);
				ErrorCount++;
			}
'\\'		{
				fprintf(ErrorFile, "Error at line %d: Unterminated Character\n\n", LineCount);
				ErrorCount++;
			}
			
'\\n'	|
'\\t'	|
'\\\\'	|
'\\\''	|
'\\\"'	|
'\\f'	|
'\\a'	|
'\\r'	|
'\\b'	|
'\\v'	|
'\\0'	{return CONST_CHAR;}

'[^\'\n][^\'\n]+'	{
				fprintf(ErrorFile, "Error at line %d: Multi character constant error\n\n", LineCount);
				ErrorCount++;
			}
			
'[^\'\n]'	{return CONST_CHAR;}
			
{ALPHANUMERIC}({ALPHANUMERIC}*{DIGIT}*)*	{
	SymbolInfo *s = new  SymbolInfo(yytext, "ID");
	yylval.Symbol = s;
	return ID;
}

"//"		{BEGIN COMMENT;}
<COMMENT>\\\n	{LineCount++;}
<COMMENT>\n	{
				BEGIN INITIAL;
				LineCount++;
			}
<COMMENT><<EOF>>	{
				BEGIN INITIAL;
				return;
}
<COMMENT>.	{}

"/*"		{BEGIN MULTICOMMENT;}
<MULTICOMMENT>"*/"	{BEGIN INITIAL; LineStart = LineCount;}
<MULTICOMMENT>\n	{LineCount++;}
<MULTICOMMENT><<EOF>>	{
				fprintf(ErrorFile, "Error at line %d: Unterminated Comment\n\n", LineStart);
				ErrorCount++;
				return;
			}
<MULTICOMMENT>.	{}


{WHITESPACE}+	{}

[^{ALPHANUMERIC}{DIGIT}\'\"]	{
				fprintf(ErrorFile, "Error at line %d: Unrecognized Character\n\n", LineCount);
				ErrorCount++;
			}

%%
