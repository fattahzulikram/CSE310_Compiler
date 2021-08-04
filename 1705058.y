%{
#include<iostream>
#include<cstdlib>
#include<cstring>
#include<cmath>
#include<string>
#include<vector>
#include "S1705058_SymbolTable.h"


using namespace std;

struct VariableIdentity{
	std::string Name;
	std::string Size;
	
	VariableIdentity(){}
	VariableIdentity(std::string name, std::string size){
		Name = name;
		Size = size;
	}
};

int yyparse(void);
int yylex(void);

std::string TypeSpecifier = ""; // Necessary For storing type_specifier 
std::string ReturnStatementType = ""; // Necessary for matching return type and definiton
struct VariableIdentity ReturnExp;
int LabelCount = 0;
int TempCount = 0;
bool ReturnCalled = false;
FILE* ErrorFile;
FILE* Log;
FILE* Assembly;
FILE* Optimized;

extern int LineCount;
extern int ErrorCount;
extern FILE *yyin;

SymbolTable *table = new SymbolTable(30);

vector<SymbolInfo*> Parameters;
vector<VariableIdentity> VariablesUsed;

void yyerror(const char *s)
{
	fprintf(ErrorFile, "Error at Line %d: %s\n\n", LineCount, s);
	ErrorCount++;
}

std::string NewLabel(){
	return "L" + std::to_string(++LabelCount);
}

std::string NewTemp(){
	struct VariableIdentity Temp;
	Temp.Name = "T" + std::to_string(++TempCount);
	Temp.Size = "0";
	VariablesUsed.push_back(Temp);
	return "T" + std::to_string(TempCount);
}

void OptimizeCode(vector<std::string> FinalCode){
	//printf("%s", FinalCode.c_str());
	std::string PreviousX = "NULL", PreviousY = "NULL";
	std::string CurrentX = "NULL", CurrentY = "NULL";
	for(int Counter=0; Counter<FinalCode.size(); Counter++){
		//Last line needs not be optimized
		if(Counter == FinalCode.size() - 1){
			fprintf(Optimized, "%s", FinalCode[Counter].c_str());
		}
		else{
			int MOVIndex = 0, Index = -1;
			//If MOV opcode is used, redundant code may arise
			while(MOVIndex<FinalCode[Counter].length()){
				if(FinalCode[Counter][MOVIndex]== 'M' && FinalCode[Counter][MOVIndex+1]== 'O' && FinalCode[Counter][MOVIndex+2]== 'V'){
					Index = MOVIndex + 4; //MOV and a space after MOV
					break;
				}
				MOVIndex++;
			}
			
			if(Index == -1){
				// No MOV found
				PreviousX = "NULL";
				PreviousY = "NULL";
				fprintf(Optimized, "%s", FinalCode[Counter].c_str());
			}
			else{
				//MOV opcode found, search the operands
				std::string Operands = "";
				bool CommaFound = false;
				CurrentX = "";
				CurrentY = "";
				
				//Ignore white spaces and get the two operands
				for(int OCounter = Index; OCounter < FinalCode[Counter].length(); OCounter++){
					if(FinalCode[Counter][OCounter] == ','){
						CommaFound = true;
					}
					else{
						if(FinalCode[Counter][OCounter] != ' ' && FinalCode[Counter][OCounter] != '\n' && CommaFound){
							CurrentY += FinalCode[Counter][OCounter];
						}
						else if(FinalCode[Counter][OCounter] != ' ' && FinalCode[Counter][OCounter] != '\n' && !CommaFound){
							CurrentX += FinalCode[Counter][OCounter];
						}
					}
				}
				if(PreviousX != "NULL" && PreviousY != "NULL"){
					//Optimize here
					if((CurrentX == PreviousY && CurrentY == PreviousX) || (CurrentX == PreviousX && CurrentY == PreviousY)){
						//This line won't go to optimized assembly
					}else{
						//No optimization here
						PreviousX = CurrentX;
						PreviousY = CurrentY;
						fprintf(Optimized, "%s", FinalCode[Counter].c_str());
					}
				}else{
					//No optimization here
					PreviousX = CurrentX;
					PreviousY = CurrentY;
					fprintf(Optimized, "%s", FinalCode[Counter].c_str());
				}
			}
		}
	}
}

vector<std::string> GetAssemblyCode(){
	vector<std::string> Code;
	
	char* Line = NULL;
	size_t Len = 0;
	ssize_t Read;
	
	while((Read = getline(&Line, &Len, Assembly)) != -1){
		char Checker;
		int Counter = 0;
		bool NotComment = true;
		bool NotBlank = true;
		
		if(Read == 1){
			NotBlank = false;
		}
		
		while(Counter < Read){
			Checker = Line[Counter];
			if(Checker == ';'){
				NotComment = false;
				break;
			}
			Counter++;
		}
		
		if(NotBlank && NotComment){
			Code.push_back(std::string(Line));
		}
	}
	return Code;
}

%}

%union{
	SymbolInfo* Symbol;
}

%token IF ELSE FOR WHILE INT FLOAT DOUBLE CHAR RETURN VOID PRINTLN DO BREAK SWITCH CASE DEFAULT CONTINUE INCOP DECOP ASSIGNOP NOT SEMICOLON COMMA LPAREN RPAREN LCURL RCURL LTHIRD RTHIRD CONST_CHAR
%token<Symbol>ADDOP
%token<Symbol>MULOP
%token<Symbol>RELOP
%token<Symbol>LOGICOP
%token<Symbol>CONST_INT
%token<Symbol>CONST_FLOAT
%token<Symbol>ID

%type<Symbol>start program unit var_declaration func_declaration func_definition type_specifier parameter_list factor variable declaration_list argument_list arguments logic_expression expression compound_statement statement rel_expression simple_expression term unary_expression expression_statement statements
%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE


%%

start : program
	{
		fprintf(Log, "Line no. %d: start : program\n\n", LineCount);
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		$$ = $1;
		if(ErrorCount == 0){
			//Start Printing Assembly
			
			//Stack Size And Model
			fprintf(Assembly, ".MODEL SMALL\n\n.STACK 100H\n\n.DATA\n");
			// Data Segment
			fprintf(Assembly, "\tADDRESS DW ?\n");
			for(int Counter=0; Counter<VariablesUsed.size(); Counter++){
				if(VariablesUsed[Counter].Size == "0"){
					fprintf(Assembly, "\t%s DW ?\n", VariablesUsed[Counter].Name.c_str());
				}
				else{
					fprintf(Assembly, "\t%s DW %s DUP (?)\n", VariablesUsed[Counter].Name.c_str(), VariablesUsed[Counter].Size.c_str());
				}
			}
			
			//CODE Segment
			fprintf(Assembly, "\n.CODE\n");
			
			//Procedure for println(id)
			fprintf(Assembly, "PRINTLN PROC\n");
			fprintf(Assembly, "\t;Store Register States\n");
			fprintf(Assembly, "\tPUSH AX\n");
			fprintf(Assembly, "\tPUSH BX\n");
			fprintf(Assembly, "\tPUSH CX\n");
			fprintf(Assembly, "\tPUSH DX\n\n");
			
			fprintf(Assembly, "\t;Divisor\n\tMOV BX, 10\n");
			fprintf(Assembly, "\t;Counter\n\tMOV CX, 0\n");
			fprintf(Assembly, "\t;For remainder\n\tMOV DX, 0\n\n");
			
			fprintf(Assembly, "\t;Check for 0 or negative\n\tCMP AX, 0\n");
			fprintf(Assembly, "\t;Print Zero\n\tJE PRINT_ZERO\n");
			fprintf(Assembly, "\t;Positive Number\n\tJNL START_STACK\n");
			fprintf(Assembly, "\t;Negative Number, Print the sign and Negate the number\n");
			fprintf(Assembly, "\tPUSH AX\n");
			fprintf(Assembly, "\tMOV AH, 2\n");
			fprintf(Assembly, "\tMOV DL, 2DH\n");
			fprintf(Assembly, "\tINT 21H\n");
			fprintf(Assembly, "\tPOP AX\n");
			fprintf(Assembly, "\tNEG AX\n");
			fprintf(Assembly, "\tMOV DX, 0\n");
			fprintf(Assembly, "\tSTART_STACK:\n");
			fprintf(Assembly, "\t\t;If AX=0, Start Printing\n");
			fprintf(Assembly, "\t\tCMP AX,0\n");
			fprintf(Assembly, "\t\tJE START_PRINTING\n");
			fprintf(Assembly, "\t\t;AX = AX / 10\n");
			fprintf(Assembly, "\t\tDIV BX\n");
			fprintf(Assembly, "\t\t;Remainder is Stored in DX\n");
			fprintf(Assembly, "\t\tPUSH DX\n");
			fprintf(Assembly, "\t\tINC CX\n");
			fprintf(Assembly, "\t\tMOV DX, 0\n");
			fprintf(Assembly, "\t\tJMP START_STACK\n");
			
			fprintf(Assembly, "\tSTART_PRINTING:\n");
			fprintf(Assembly, "\t\tMOV AH, 2\n");
			fprintf(Assembly, "\t\t;Counter becoming 0 implies that the number has been printed\n");
			fprintf(Assembly, "\t\tCMP CX, 0\n");
			fprintf(Assembly, "\t\tJE DONE_PRINTING\n");
			fprintf(Assembly, "\t\tPOP DX\n");
			fprintf(Assembly, "\t\t;To get the ASCII Equivalent\n\t\tADD DX, 30H\n");
			fprintf(Assembly, "\t\tINT 21H\n");
			fprintf(Assembly, "\t\tDEC CX\n");
			fprintf(Assembly, "\t\tJMP START_PRINTING\n");
			
			fprintf(Assembly, "\tPRINT_ZERO:\n");
			fprintf(Assembly, "\t\tMOV AH, 2\n");
			fprintf(Assembly, "\t\tMOV DX, 30H\n");
			fprintf(Assembly, "\t\tINT 21H\n");
			
			fprintf(Assembly, "\tDONE_PRINTING:\n");
			fprintf(Assembly, "\t\t;Print a New Line\n");
			fprintf(Assembly, "\t\tMOV DL, 0AH\n");
			fprintf(Assembly, "\t\tINT 21H\n");
			fprintf(Assembly, "\t\tMOV DL, 0DH\n");
			fprintf(Assembly, "\t\tINT 21H\n");
			
			fprintf(Assembly, "\t;Restore Register States and Return\n");
			fprintf(Assembly, "\tPOP DX\n");
			fprintf(Assembly, "\tPOP CX\n");
			fprintf(Assembly, "\tPOP BX\n");
			fprintf(Assembly, "\tPOP AX\n");
			fprintf(Assembly, "\tRET\n");
			fprintf(Assembly, "PRINTLN ENDP\n\n");
			
			//Print The Rest of the codes
			fprintf(Assembly, "%s", $1->GetCode().c_str());
			fprintf(Assembly, "\tEND MAIN");
		}
	}
	;

program : program unit 
	{
		fprintf(Log, "Line no. %d: program : program unit\n\n", LineCount);
		$1->SetSymbolName($1->GetSymbolName() + "\n" + $2->GetSymbolName());
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		$$=$1;
		$$->SetCode($1->GetCode()+$2->GetCode());
	}
	| unit
	{
		fprintf(Log, "Line no. %d: program : unit\n\n", LineCount);
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		SymbolInfo* Prog = new SymbolInfo($1->GetSymbolName(), "program");
		Prog->SetCode($1->GetCode());
		$$ = Prog;
	}
	;
	
unit : var_declaration
	{
		fprintf(Log, "Line no. %d: unit : var_declaration\n\n", LineCount);
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		SymbolInfo* Sym = new SymbolInfo($1->GetSymbolName(), "unit");
		Sym->SetCode($1->GetCode());
		$$ = Sym;
	}
    | func_declaration
    {
		fprintf(Log, "Line no. %d: unit : func_declaration\n\n", LineCount);
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		SymbolInfo* Sym = new SymbolInfo($1->GetSymbolName(), "unit");
		Sym->SetCode($1->GetCode());
		$$ = Sym;
	}
    | func_definition
    {
		fprintf(Log, "Line no. %d: unit : func_definition\n\n", LineCount);
		fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
		SymbolInfo* Sym = new SymbolInfo($1->GetSymbolName(), "unit");
		Sym->SetCode($1->GetCode());
		$$ = Sym;
	}
    ;
     
func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON
		{
			fprintf(Log, "Line no. %d: func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON\n\n", LineCount);
			
			SymbolInfo* Sym = new SymbolInfo($2->GetSymbolName(), "ID");
			
			// This Function Is Already Declared Once
			if(table->LookUp($2->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Previous Declaration of Function \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Previous Declaration of Function \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
				ErrorCount++;
			}
			// Unique name
			else{
				Sym->SetReturnType($1->GetSymbolType());
				Sym->SetIdentity("func_declaration");
				
				for(int Counter = 0; Counter < $4->ParamList.size(); Counter++){
					Sym->ParamList.push_back($4->ParamList[Counter]);
				}
				table->Insert(Sym);
			}
			
			std::string Line = "";
			Line += $1->GetSymbolType() + " " + $2->GetSymbolName() + "(";
			
			for(int Counter = 0; Counter < $4->ParamList.size(); Counter++){
				if($4->ParamList[Counter]->GetIdentity() == "Type_Only")	Line += $4->ParamList[Counter]->GetSymbolType();
				else Line += $4->ParamList[Counter]->GetSymbolType() + " " + $4->ParamList[Counter]->GetSymbolName();
				
				if(Counter != $4->ParamList.size() - 1){
					Line += ", ";
				}
			}
			Line += ");";
			
			SymbolInfo* sym = new SymbolInfo(Line, "function_declaration");
			$$ = sym;
			
			fprintf(Log, "%s\n\n", Line.c_str());
			
			// parameter_list populated Parameter vector, so it needs to be cleared
			Parameters.clear();
			
		}
		| type_specifier ID LPAREN RPAREN SEMICOLON
		{
			fprintf(Log, "Line no. %d: func_declaration : type_specifier ID LPAREN parameter_list RPAREN SEMICOLON\n\n", LineCount);
			
			SymbolInfo* Sym = new SymbolInfo($2->GetSymbolName(), "ID");
			
			// This Function Is Already Declared Once
			if(table->LookUp($2->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Previous Declaration of Function \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Previous Declaration of Function \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
				ErrorCount++;
			}else{
				Sym->SetReturnType($1->GetSymbolType());
				Sym->SetIdentity("func_declaration");
				table->Insert(Sym);
			}
			
			std::string Line = "";
			Line += $1->GetSymbolType() + " " + $2->GetSymbolName() + "();";
			
			SymbolInfo* sym = new SymbolInfo(Line, "function_declaration");
			$$ = sym;
			
			fprintf(Log, "%s\n\n", Line.c_str());
			
			// No parameter_list was used, so Parameters needs not be cleared
		}
		;

// Mid Action Rules are used for specific tasks
func_definition : type_specifier ID LPAREN parameter_list RPAREN LCURL{
			// compound_statement, which has an LCURL, will need a new scope first
			table->EnterScope(Log);
			
			// Since parameter_list is used, the parameters stored in Parameters vector will populate the new scope
			for(int Counter = 0; Counter < Parameters.size(); Counter++){
				SymbolInfo* ParamToInsert = new SymbolInfo(Parameters[Counter]->GetSymbolName(), Parameters[Counter]->GetSymbolType());
				ParamToInsert->SetVariableType(Parameters[Counter]->GetVariableType());
				
				// Variable already exists in current scope
				
				if(table->LookUpCurrentScope(Parameters[Counter]->GetSymbolName())){
					fprintf(ErrorFile, "Error at Line %d: Multiple Declaration of \'%s\'\n\n", LineCount, Parameters[Counter]->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Multiple Declaration of \'%s\'\n\n", LineCount, Parameters[Counter]->GetSymbolName().c_str());
					ErrorCount++;
				}else{
					table->Insert(ParamToInsert);
					
					//For Assembly
					struct VariableIdentity Temp;
					Temp.Name = Parameters[Counter]->GetSymbolName() + table->GetCurrentScopeID();
					Temp.Size = "0";
					VariablesUsed.push_back(Temp);
				}
			}	
			//Parameters.clear();	
		} statements RCURL
		{
			fprintf(Log, "Line no. %d: func_definition : type_specifier ID LPAREN parameter_list RPAREN compound_statement\n\n", LineCount);
			std::string Lines = "";
			Lines += $1->GetSymbolType() + " " + $2->GetSymbolName() + "(";
			
			for(int Counter = 0; Counter < $4->ParamList.size(); Counter++){
				Lines += $4->ParamList[Counter]->GetSymbolType() + " " + $4->ParamList[Counter]->GetSymbolName();
				if(Counter != $4->ParamList.size() - 1){
					Lines += ", ";
				}
			}
			Lines += "){\n"; //+ $8->GetSymbolName() + "\n}";
			for(int Counter = 0; Counter < $8->ParamList.size(); Counter++){
				Lines += $8->ParamList[Counter]->GetSymbolName() + "\n";
			}
			Lines += "}";
			
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			SymbolInfo* FuncDef = new SymbolInfo(Lines, "func_definition");
			$$ = FuncDef;
			
			//Generate Assembly Code
			std::string AssCode = "";
			if($2->GetSymbolName() == "main"){
				AssCode += "MAIN PROC\n";
				AssCode += "\t;Initialize Data Segment\n";
				AssCode += "\tMOV AX, @DATA\n";
				AssCode += "\tMOV DS, AX\n\n";
			}else{
				AssCode += $2->GetSymbolName() + " PROC\n";
				AssCode += "\t;Save Address\n";
				AssCode += "\tPOP ADDRESS\n\n";
				AssCode += "\t;Get Function Parameters\n";
				
				for(int Counter = Parameters.size() - 1; Counter >= 0; Counter--){
					AssCode += "\tPOP " + Parameters[Counter]->GetSymbolName() + table->GetCurrentScopeID() + "\n";
				}
			}
			
			AssCode += $8->GetCode();
			
			if($2->GetSymbolName() == "main"){
				AssCode += "\t;End of main\n";
				AssCode += "\tMOV AH, 4CH\n";
				AssCode += "\tINT 21H\n";
				AssCode += "MAIN ENDP\n";
			}
			else{
				AssCode += "\t;Push Return Value\n";
				
				if(ReturnStatementType != ""){
					if(ReturnExp.Size == "0"){
						//AssCode += "\tMOV AX, " + ReturnExp.Name + "\n";
						AssCode += "\tPUSH " + ReturnExp.Name + "\n";
					}else{
						AssCode += "\tLEA SI, " + ReturnExp.Name + "\n";
						AssCode += "\tADD SI, " + ReturnExp.Size + "*2\n";
						//AssCode += "\tMOV AX, [SI]\n";
						AssCode += "\tPUSH [SI]\n";
					}
				}
				AssCode += "\tPUSH ADDRESS\n";
				AssCode += "\tRET\n";
				AssCode += $2->GetSymbolName() + " ENDP\n\n";
			}
			
			$$->SetCode(AssCode);
			
			bool ReturnTypeErrorFound = false;
			
			// Check if the function was DECLARED before
			SymbolInfo* Declared = table->LookUp($2->GetSymbolName());
			
			// The name exists in the scopetable
			if(Declared){
				// If the name is not of a DECLARATION, then its an error
				if(Declared->GetIdentity() != "func_declaration"){
					fprintf(ErrorFile, "Error at Line %d: Previous Definition of \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Previous Definition of \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
					ErrorCount++;
				}
				// DECLARATION found, now to see if parameter counts match
				else if(Declared->ParamList.size() != $4->ParamList.size()){
					fprintf(ErrorFile, "Error at Line %d: Parameter Count Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Parameter Count Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
					ErrorCount++;
				}
				// Everything in order, now to see if parameter list match
				else{
					bool Match = true;
					
					for(int Counter = 0; Counter < $4->ParamList.size(); Counter ++){
						// Check if type specifier matches
						if(Declared->ParamList[Counter]->GetSymbolType() != $4->ParamList[Counter]->GetSymbolType()){
							Match = false;
							break;
						}
					}
					// Parameters matched
					if(Match){
						// Now check if the return statement matched with the declaration
						if($1->GetSymbolType() == Declared->GetReturnType()){
							// The function definition is complete, no further definition should be allowed, so, Declared should be marked as Defined in the SymbolTable
							Declared->SetIdentity("function_definition");
							Declared->SetImplementationID(table->GetCurrentScopeID());
						}
						else{
							fprintf(ErrorFile, "Error at Line %d: Return Type Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
							fprintf(Log, "Error at Line %d: Return Type Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
							ErrorCount++;
							ReturnTypeErrorFound = true;
						}
					}
					// Parameters Did Not Match
					else{
						fprintf(ErrorFile, "Error at Line %d: Parameters Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
						fprintf(Log, "Error at Line %d: Parameters Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
						ErrorCount++;
					}
					
				}
			}
			
			// The Name Does Not Exist in the ScopeTable, So, It was not Declared before
			else{
				SymbolInfo* Defined = new SymbolInfo($2->GetSymbolName(), "ID");
				Defined->SetIdentity("function_definition");
				Defined->SetReturnType($1->GetSymbolType());
				
				for(int Counter = 0; Counter < Parameters.size(); Counter++){
					Defined->ParamList.push_back(Parameters[Counter]);
				}
				Defined->SetImplementationID(table->GetCurrentScopeID());
				table->InsertToGlobalScope(Defined);
			}
			
			if(!ReturnTypeErrorFound){
				// Match return type with definition
				// A void function with return statement of other type
				if($1->GetSymbolType() == "void" && ReturnStatementType != ""){
					fprintf(ErrorFile, "Error at Line %d: Return With Value in Function Returning Void\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Return With Value in Function Returning Void\n\n", LineCount);
					ErrorCount++;
				}
				// A non void function without a return type
				else if($1->GetSymbolType() != "void" && ReturnStatementType == ""){
					if($2->GetSymbolName() == "main"){}
					else{
						fprintf(ErrorFile, "Error at Line %d: Return With No Value in Function Returning Non-Void\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Return With No Value in Function Returning Non-Void\n\n", LineCount);
						ErrorCount++;
					}
				}
				// Mismatch in return type except void
				else if($1->GetSymbolType() != "void" && $1->GetSymbolType() != ReturnStatementType){
					if($1->GetSymbolType() == "float" && ReturnStatementType == "int"){}
					else{
						fprintf(ErrorFile, "Error at Line %d: Incompatible Return Type\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Incompatible Return Type\n\n", LineCount);
						ErrorCount++;
					}
				}
				ReturnStatementType = "";
			}
			ReturnCalled = false;
			Parameters.clear();
			
			// Exit the scope
			table->PrintAllScopes(Log);
			table->ExitScope(Log);
		}
		| type_specifier ID LPAREN RPAREN LCURL{
			// This time, just creating a new scope is enough
			table->EnterScope(Log);
		} statements RCURL
		{
			fprintf(Log, "Line no. %d: func_definition : type_specifier ID LPAREN RPAREN compound_statement\n\n", LineCount);
			std::string Lines = "";
			Lines += $1->GetSymbolType() + " " + $2->GetSymbolName() + "(){\n";//+ $7->GetSymbolName() + "\n}";
			for(int Counter = 0; Counter < $7->ParamList.size(); Counter++){
				Lines += $7->ParamList[Counter]->GetSymbolName() + "\n";
			}
			Lines += "}";
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			SymbolInfo* FuncDef = new SymbolInfo(Lines, "func_definition");
			$$ = FuncDef;
			
			//Generate Assembly Code
			std::string AssCode = "";
			if($2->GetSymbolName() == "main"){
				AssCode += "MAIN PROC\n";
				AssCode += "\t;Initialize Data Segment\n";
				AssCode += "\tMOV AX, @DATA\n";
				AssCode += "\tMOV DS, AX\n\n";
			}else{
				AssCode += $2->GetSymbolName() + " PROC\n";
				AssCode += "\t;Save Address\n";
				AssCode += "\tPOP ADDRESS\n\n";
			}
			
			AssCode += $7->GetCode();
			
			if($2->GetSymbolName() == "main"){
				AssCode += "\t;End of main\n";
				AssCode += "\tMOV AH, 4CH\n";
				AssCode += "\tINT 21H\n";
				AssCode += "MAIN ENDP\n";
			}
			else{
				AssCode += "\t;Push Return Value\n";
				if(ReturnStatementType != ""){
					if(ReturnExp.Size == "0"){
						//AssCode += "\tMOV AX, " + ReturnExp.Name + "\n";
						AssCode += "\tPUSH " + ReturnExp.Name + "\n";
					}else{
						AssCode += "\tLEA SI, " + ReturnExp.Name + "\n";
						AssCode += "\tADD SI, " + ReturnExp.Size + "*2\n";
						//AssCode += "\tMOV AX, [SI]\n";
						AssCode += "\tPUSH [SI]\n";
					}
				}
				AssCode += "\tPUSH ADDRESS\n";
				AssCode += "\tRET\n";
				AssCode += $2->GetSymbolName() + " ENDP\n\n";
			}
			
			$$->SetCode(AssCode);
			
			bool ReturnTypeErrorFound = false;
			
			// Check if the function was DECLARED before
			SymbolInfo* Declared = table->LookUp($2->GetSymbolName());
			
			// The name exists in the scopetable
			if(Declared){
				// If the name is not of a DECLARATION, then its an error
				if(Declared->GetIdentity() != "func_declaration"){
					fprintf(ErrorFile, "Error at Line %d: Previous Definition of \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Previous Definition of \'%s\' Found\n\n", LineCount, $2->GetSymbolName().c_str());
					ErrorCount++;
				}
				// DECLARATION found, the function can't have any parameters declared before
				else if(Declared->ParamList.size() > 0){
					fprintf(ErrorFile, "Error at Line %d: Parameter Count Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Parameter Count Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
					ErrorCount++;
				}
				// Everything is fine
				else{
					// Now check if the return statement matched with the declaration
					if($1->GetSymbolType() == Declared->GetReturnType()){
						// The function definition is complete, no further definition should be allowed, so, Declared should be marked as Defined in the SymbolTable
						Declared->SetIdentity("function_definition");
						Declared->SetImplementationID(table->GetCurrentScopeID());
					}
					else{
						fprintf(ErrorFile, "Error at Line %d: Return Type Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
						fprintf(Log, "Error at Line %d: Return Type Of \'%s\' Does Not Match With The Declaration\n\n", LineCount, $2->GetSymbolName().c_str());
						ErrorCount++;
						ReturnTypeErrorFound = true;
					}
				}
			}
			// The Name Does Not Exist in the ScopeTable, So, It was not Declared before
			else{
				// Exit the scope
				SymbolInfo* Defined = new SymbolInfo($2->GetSymbolName(), "ID");
				Defined->SetIdentity("function_definition");
				Defined->SetReturnType($1->GetSymbolType());
				Defined->SetImplementationID(table->GetCurrentScopeID());
				table->InsertToGlobalScope(Defined);
			}
			
			if(!ReturnTypeErrorFound){
				// Match return type with definition
				// A void function with return statement of other type
				if($1->GetSymbolType() == "void" && ReturnStatementType != ""){
					fprintf(ErrorFile, "Error at Line %d: Return With Value in Function Returning Void\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Return With Value in Function Returning Void\n\n", LineCount);
					ErrorCount++;
				}
				// A non void function without a return type
				else if($1->GetSymbolType() != "void" && ReturnStatementType == ""){
					if($2->GetSymbolName() == "main"){}
					else{
						fprintf(ErrorFile, "Error at Line %d: Return With No Value in Function Returning Non-Void\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Return With No Value in Function Returning Non-Void\n\n", LineCount);
						ErrorCount++;
					}
				}
				// Mismatch in return type
				else if($1->GetSymbolType() != "void" && $1->GetSymbolType() != ReturnStatementType){
					if($1->GetSymbolType() == "float" && ReturnStatementType == "int"){}
					else{
						fprintf(ErrorFile, "Error at Line %d: Incompatible Return Type\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Incompatible Return Type\n\n", LineCount);
						ErrorCount++;
					}
				}
				ReturnStatementType = "";
			}
			ReturnCalled = false;
			// Exit the scope
			table->PrintAllScopes(Log);
			table->ExitScope(Log);
		}
 		;				


parameter_list  : parameter_list COMMA type_specifier ID
		{
			fprintf(Log, "Line no. %d: parameter_list  : parameter_list COMMA type_specifier ID\n\n", LineCount);
			
			SymbolInfo* NewParam = new SymbolInfo($4->GetSymbolName(),$3->GetSymbolType());
			NewParam->SetIdentity("Variable"); 
			NewParam->SetVariableType($3->GetSymbolType());
			$$->ParamList.push_back(NewParam);
			
			SymbolInfo* IDParam = new SymbolInfo($4->GetSymbolName(), "ID");
			IDParam->SetVariableType($3->GetSymbolType());
			Parameters.push_back(IDParam);
			
			for(int Counter = 0; Counter < $$->ParamList.size(); Counter++){
				if($$->ParamList[Counter]->GetIdentity() == "Type_Only") fprintf(Log, "%s", $$->ParamList[Counter]->GetSymbolType().c_str());
				else fprintf(Log, "%s %s", $$->ParamList[Counter]->GetSymbolType().c_str(), $$->ParamList[Counter]->GetSymbolName().c_str());
				if(Counter != $$->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			
			fprintf(Log, "\n\n");
		}
		| parameter_list COMMA type_specifier
		{
			fprintf(Log, "Line no. %d: parameter_list  : parameter_list COMMA type_specifier\n\n", LineCount);
			
			SymbolInfo* NewParam = new SymbolInfo("",$3->GetSymbolType());
			NewParam->SetIdentity("Type_Only"); 
			$$->ParamList.push_back(NewParam);
			
			for(int Counter = 0; Counter < $$->ParamList.size(); Counter++){
				if($$->ParamList[Counter]->GetIdentity() == "Type_Only") fprintf(Log, "%s", $$->ParamList[Counter]->GetSymbolType().c_str());
				else fprintf(Log, "%s %s", $$->ParamList[Counter]->GetSymbolType().c_str(), $$->ParamList[Counter]->GetSymbolName().c_str());
				if(Counter != $$->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			
			fprintf(Log, "\n\n");
		}
 		| type_specifier ID
 		{
			fprintf(Log, "Line no. %d: parameter_list  : type_specifier ID\n\n", LineCount);
			
			// Need A SymbolInfo To Contain The List
			SymbolInfo* List = new SymbolInfo("parameter_list");
			$$ = List;
			
			// Insert This Parameter Into the List
			SymbolInfo* NewParam = new SymbolInfo($2->GetSymbolName(),$1->GetSymbolType());
			NewParam->SetIdentity("Variable"); 
			NewParam->SetVariableType($1->GetSymbolType());
			$$->ParamList.push_back(NewParam);
			
			// The variable Parameters stores the names of the IDs, if needed, they can be used to populate a new scope, for example, when a function definition is being used
			// If not needed, the variable is cleared later
			SymbolInfo* IDParam = new SymbolInfo($2->GetSymbolName(), "ID");
			IDParam->SetVariableType($1->GetSymbolType());
			Parameters.push_back(IDParam);
			
			
			fprintf(Log, "%s %s\n\n", $1->GetSymbolType().c_str(), $2->GetSymbolName().c_str());
		}
		| type_specifier
		{
			fprintf(Log, "Line no. %d: parameter_list  : type_specifier\n\n", LineCount);
			
			// Need A SymbolInfo To Contain The List
			SymbolInfo* List = new SymbolInfo("parameter_list");
			$$ = List;
			
			// Insert This Parameter Into the List
			SymbolInfo* NewParam = new SymbolInfo("",$1->GetSymbolType());
			NewParam->SetIdentity("Type_Only"); 
			$$->ParamList.push_back(NewParam);
			
			fprintf(Log, "%s\n\n", $1->GetSymbolType().c_str());
		}
 		;

 		
compound_statement : LCURL{
			//table->EnterScope(Log);		
		} statements RCURL
		{
			fprintf(Log, "Line no. %d: compound_statement : LCURL statements RCURL\n\n", LineCount);
			
			std::string Lines = "";
			Lines += "{\n";
			for(int Counter = 0; Counter < $3->ParamList.size(); Counter++){
				Lines += $3->ParamList[Counter]->GetSymbolName() + "\n";
			}
			Lines += "}";
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			$$ = $3;
			$$->SetSymbolName(Lines);
			$$->SetSymbolType("compound_statement");
			//table->PrintAllScopes(Log);
			//table->ExitScope(Log);
		}
 		| LCURL RCURL
		{
			fprintf(Log, "Line no. %d: compound_statement : LCURL RCURL\n\n", LineCount);
			fprintf(Log, "{}\n\n");
			
			SymbolInfo* ComStat = new SymbolInfo("{}", "compound_statement");
			$$ = ComStat;
		}
 		;
 		    
var_declaration : type_specifier declaration_list SEMICOLON
		{
			fprintf(Log, "Line no. %d: var_declaration : type_specifier declaration_list SEMICOLON\n\n", LineCount);
			std::string Lines = "";
			
			Lines += $1->GetSymbolType() + " ";
			for(int Counter = 0; Counter < $2->ParamList.size(); Counter++){
				Lines += $2->ParamList[Counter]->GetSymbolName();
				if($2->ParamList[Counter]->GetIdentity() == "array"){
					Lines += "[" + std::to_string($2->ParamList[Counter]->GetVariableSize()) + "]";
				}
				if(Counter != $2->ParamList.size()-1){
					Lines += ", ";
				}
			}
			Lines += ";";
			
			SymbolInfo* VarDec = new SymbolInfo(Lines, "var_declaration");
			$$ = VarDec;
			// Did not Generate Any Code, Since the Declaration Part Will be Done on program rule
			
			// Void Variable is not allowed
			if($1->GetSymbolType() == "void"){
				fprintf(ErrorFile, "Error at Line %d: Variable or Field Declared Void\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Variable or Field Declared Void\n\n", LineCount);
				ErrorCount++;
			}
			fprintf(Log, "%s\n\n", Lines.c_str());
			$2->ParamList.clear();
		}
 		;
 		 
type_specifier : INT
		{
			fprintf(Log, "Line no. %d: type_specifier : INT\n\n", LineCount);
			TypeSpecifier = "int";
			
			SymbolInfo* TypeSpec = new SymbolInfo("int");
			$$ = TypeSpec;
			
			fprintf(Log, "%s\n\n", $$->GetSymbolType().c_str());
		}
 		| FLOAT
 		{
			fprintf(Log, "Line no. %d: type_specifier : FLOAT\n\n", LineCount);
			TypeSpecifier = "float";
			
			SymbolInfo* TypeSpec = new SymbolInfo("float");
			$$ = TypeSpec;
			
			fprintf(Log, "%s\n\n", $$->GetSymbolType().c_str());
		}
 		| VOID
 		{
			fprintf(Log, "Line no. %d: type_specifier : VOID\n\n", LineCount);
			TypeSpecifier = "void";
			
			SymbolInfo* TypeSpec = new SymbolInfo("void");
			$$ = TypeSpec;
			
			fprintf(Log, "%s\n\n", $$->GetSymbolType().c_str());
		}
 		;
 		
declaration_list : declaration_list COMMA ID
		{
			fprintf(Log, "Line no. %d: declaration_list : declaration_list COMMA ID\n\n", LineCount);
			
			SymbolInfo* Temp = new SymbolInfo($3->GetSymbolName(), $3->GetSymbolType());
			Temp->SetVariableType(TypeSpecifier);
			Temp->SetIdentity("Variable");
			if(table->GetCurrentScopeID() == "1"){
				Temp->GlobalVar = true;
			}
			$$->ParamList.push_back(Temp);
			
			struct VariableIdentity VarID;
			VarID.Name = $3->GetSymbolName() + table->GetCurrentScopeID();
			VarID.Size = "0";
			VariablesUsed.push_back(VarID);
			
			// Variable Already Declared
			if(table->LookUpCurrentScope($3->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $3->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $3->GetSymbolName().c_str());
				ErrorCount++;
			}
			else if(TypeSpecifier != "void"){ 
				table->Insert(Temp);
			}
			
			// Print the List
			for(int Counter = 0; Counter < $$->ParamList.size(); Counter++){
				fprintf(Log, "%s", $$->ParamList[Counter]->GetSymbolName().c_str());
				if($$->ParamList[Counter]->GetIdentity() == "array"){
					fprintf(Log, "[%d]", $$->ParamList[Counter]->GetVariableSize());
				}
				if(Counter != $$->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			fprintf(Log, "\n\n");
		}
 		| declaration_list COMMA ID LTHIRD CONST_INT RTHIRD
		{
			fprintf(Log, "Line no. %d: declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD\n\n", LineCount);
			int ArraySize = std::atoi($5->GetSymbolName().c_str());
			
			SymbolInfo* Temp = new SymbolInfo($3->GetSymbolName(), $3->GetSymbolType());
			Temp->SetVariableType(TypeSpecifier);
			Temp->SetIdentity("array");
			Temp->SetVariableSize(ArraySize);
			$$->ParamList.push_back(Temp);
			
			struct VariableIdentity VarID;
			VarID.Name = $3->GetSymbolName() + table->GetCurrentScopeID();
			VarID.Size = $5->GetSymbolName();
			VariablesUsed.push_back(VarID);
			
			// Array of 0 or negative size
			if(ArraySize < 1){
				fprintf(ErrorFile, "Error at Line %d: Cannot allocate an array of constant size %s\n\n", LineCount, $5->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Cannot allocate an array of constant size %s\n\n", LineCount, $5->GetSymbolName().c_str());
				ErrorCount++;
			}
			// Variable Already Declared
			else if(table->LookUpCurrentScope($3->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $3->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $3->GetSymbolName().c_str());
				ErrorCount++;
			}
			else if(TypeSpecifier != "void"){
				if(TypeSpecifier == "int") Temp->CreateIntegerArray();
				else if(TypeSpecifier == "float") Temp->CreateFloatArray();
				else if(TypeSpecifier == "char") Temp->CreateCharacterArray();
				table->Insert(Temp);
			}
			
			// Print the List
			for(int Counter = 0; Counter < $$->ParamList.size(); Counter++){
				fprintf(Log, "%s", $$->ParamList[Counter]->GetSymbolName().c_str());
				if($$->ParamList[Counter]->GetIdentity() == "array"){
					fprintf(Log, "[%d]", $$->ParamList[Counter]->GetVariableSize());
				}
				if(Counter != $$->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			fprintf(Log, "\n\n");
		}
 		| ID
		{
			fprintf(Log, "Line no. %d: declaration_list : ID\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			
			SymbolInfo* List = new SymbolInfo("declaration_list");
			List->SetIdentity("declaration_list");
			$$ = List;
			
			SymbolInfo* Temp = new SymbolInfo($1->GetSymbolName(), $1->GetSymbolType());
			Temp->SetVariableType(TypeSpecifier);
			Temp->SetIdentity("Variable");
			if(table->GetCurrentScopeID() == "1"){
					Temp->GlobalVar = true;
			}
			$$->ParamList.push_back(Temp);
			
			struct VariableIdentity VarID;
			VarID.Name = $1->GetSymbolName() + table->GetCurrentScopeID();
			VarID.Size = "0";
			VariablesUsed.push_back(VarID);
			
			// Variable Already Declared
			if(table->LookUpCurrentScope($1->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
			}
			else if(TypeSpecifier != "void"){
				table->Insert(Temp);
			}
			
		}
 		| ID LTHIRD CONST_INT RTHIRD
		{
			fprintf(Log, "Line no. %d: declaration_list : ID LTHIRD CONST_INT RTHIRD\n\n", LineCount);
			fprintf(Log, "%s[%s]\n\n", $1->GetSymbolName().c_str(), $3->GetSymbolName().c_str());
			
			SymbolInfo* List = new SymbolInfo("declaration_list");
			List->SetIdentity("declaration_list");
			$$ = List;
			int ArraySize = std::atoi($3->GetSymbolName().c_str());
			
			SymbolInfo* Temp = new SymbolInfo($1->GetSymbolName(), $1->GetSymbolType());
			Temp->SetVariableType(TypeSpecifier);
			Temp->SetIdentity("array");
			Temp->SetVariableSize(ArraySize);
			$$->ParamList.push_back(Temp);
			
			struct VariableIdentity VarID;
			VarID.Name = $1->GetSymbolName() + table->GetCurrentScopeID();
			VarID.Size = $3->GetSymbolName();
			VariablesUsed.push_back(VarID);
			
			// Array of 0 or negative size
			if(ArraySize < 1){
				fprintf(ErrorFile, "Error at Line %d: Cannot allocate an array of constant size %s\n\n", LineCount, $3->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Cannot allocate an array of constant size %s\n\n", LineCount, $3->GetSymbolName().c_str());
				ErrorCount++;
			}
			// Variable Already Declared
			else if(table->LookUpCurrentScope($1->GetSymbolName())){
				fprintf(ErrorFile, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Multiple Declaration of \'%s\' In Current Scope\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
			}
			else if(TypeSpecifier != "void"){
				if(TypeSpecifier == "int") Temp->CreateIntegerArray();
				else if(TypeSpecifier == "float") Temp->CreateFloatArray();
				else if(TypeSpecifier == "char") Temp->CreateCharacterArray();
				table->Insert(Temp);
			}
		}
 		;
 		  
statements : statement
		{
			fprintf(Log, "Line no. %d: statements : statement\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			
			SymbolInfo* Statements = new SymbolInfo("statements");
			Statements->ParamList.push_back($1);
			$$ = Statements;
			$$->SetCode($1->GetCode());
		}
	    | statements statement
		{
			fprintf(Log, "Line no. %d: statements : statements statement\n\n", LineCount);
			std::string Lines = "";
			$$ = $1;
			$$->ParamList.push_back($2);
			for(int Counter = 0; Counter < $1->ParamList.size(); Counter++){
				Lines += $1->ParamList[Counter]->GetSymbolName() + "\n";
			}
			fprintf(Log, "%s\n\n", Lines.c_str());
			$$->SetCode($1->GetCode() + $2->GetCode());
		}
	    ;
	   
statement : var_declaration
		{
			fprintf(Log, "Line no. %d: statement : var_declaration\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("statement");
		}
	    | expression_statement
		{
			fprintf(Log, "Line no. %d: statement : expression_statement\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("statement");
		}
	    | compound_statement
		{
			fprintf(Log, "Line no. %d: statement : compound_statement\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("statement");
		}
	    | FOR LPAREN expression_statement expression_statement expression RPAREN statement
		{
			fprintf(Log, "Line no. %d: statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement\n\n", LineCount);
			std::string Lines = "";
			Lines += "for(" + $3->GetSymbolName() + $4->GetSymbolName() + $5->GetSymbolName() + ")" + $7->GetSymbolName();
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			std::string LoopLabel = NewLabel();
			std::string DoneLabel = NewLabel();
			std::string AssCode = "\t;for loop\n";
			
			/*
				1. Initialize ($3)
				2. Label, Comparison to see if loop is running ($4)
				3. Loop Body ($7)
				4. Update Loop Variable ($5)
				5. Goto 2
				6. Label, Exit
			*/
			
			AssCode += $3->GetCode();
			AssCode += LoopLabel + ":\n";
			AssCode += $4->GetCode();
			AssCode += "\tMOV AX, " + $4->GetAssemblySymbol() + "\n";
			AssCode += "\tCMP AX, 0\n";
			AssCode += "\tJE " + DoneLabel + "\n";
			AssCode += $7->GetCode();
			AssCode += $5->GetCode();
			AssCode += "\tJMP " + LoopLabel + "\n\n";
			AssCode += DoneLabel + ":\n";
			
			SymbolInfo* Stat = new SymbolInfo(Lines, "statement");
			$$ = Stat;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    | IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
		{
			fprintf(Log, "Line no. %d: statement : IF LPAREN expression RPAREN statement\n\n", LineCount);
			std::string Lines = "";
			Lines += "if(" + $3->GetSymbolName() + ")" + $5->GetSymbolName();
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			std::string Else = NewLabel();
			std::string AssCode = $3->GetCode();
			AssCode += "\t;if(" + $3->GetSymbolName() + ")\n";
			AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
			AssCode += "\tCMP AX, 0\n";
			AssCode += "\tJE " + Else + "\n";
			AssCode += $5->GetCode();
			AssCode += Else + ":\n";
			
			SymbolInfo* Stat = new SymbolInfo(Lines, "statement");
			$$ = Stat;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    | IF LPAREN expression RPAREN statement ELSE statement
		{
			fprintf(Log, "Line no. %d: statement : IF LPAREN expression RPAREN statement ELSE statement\n\n", LineCount);
			std:: string Lines = "";
			Lines += "if(" + $3->GetSymbolName() + ")" + $5->GetSymbolName() + "else" + $7->GetSymbolName();
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			std::string Else = NewLabel();
			std::string DoneLabel = NewLabel();
			std::string AssCode = $3->GetCode();
			AssCode += "\t;if(" + $3->GetSymbolName() + ")...else...\n";
			AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
			AssCode += "\tCMP AX, 0\n";
			AssCode += "\tJE " + Else + "\n";
			AssCode += $5->GetCode();
			AssCode += "\tJMP " + DoneLabel + "\n\n";
			
			AssCode += Else + ":\n";
			AssCode += $7->GetCode();
			
			AssCode += DoneLabel + ":\n";
			
			SymbolInfo* Stat = new SymbolInfo(Lines, "statement");
			$$ = Stat;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    | WHILE LPAREN expression RPAREN statement
		{
			fprintf(Log, "Line no. %d: statement : WHILE LPAREN expression RPAREN statement\n\n", LineCount);
			std::string Lines = "";
			Lines += "while(" + $3->GetSymbolName() + ")" + $5->GetSymbolName();
			fprintf(Log, "%s\n\n", Lines.c_str());
			
			/*
				1. Comparison to see if loop runs
				2. Loop Body
				3. Goto 1
				4. Exit
			*/
			
			std::string LoopLabel = NewLabel();
			std::string DoneLabel = NewLabel();
			std::string AssCode = "\t;while()\n";
			AssCode += LoopLabel + ":\n";
			AssCode += $3->GetCode();
			AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
			AssCode += "\tCMP AX, 0\n";
			AssCode += "\tJE " + DoneLabel + "\n";
			AssCode += $5->GetCode();
			AssCode += "\tJMP " + LoopLabel + "\n\n";
			AssCode += DoneLabel + ":\n";
			
			SymbolInfo* Stat = new SymbolInfo(Lines, "statement");
			$$ = Stat;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    | PRINTLN LPAREN ID RPAREN SEMICOLON
		{
			fprintf(Log, "Line no. %d: statement : PRINTLN LPAREN ID RPAREN SEMICOLON\n\n", LineCount);
			std::string Line = "println(" + $3->GetSymbolName() + ");";
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Stat = new SymbolInfo(Line, "statement");
			$$ = Stat;
			
			SymbolInfo* Var = table->LookUp($3->GetSymbolName());
			if(!Var){
				fprintf(ErrorFile, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $3->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $3->GetSymbolName().c_str());
				ErrorCount++;
			}
			std::string AssCode = "\t;println(" + $3->GetSymbolName() + ")\n";
			if(Var->GlobalVar){
				AssCode += "\tMOV AX, " + $3->GetSymbolName() + "1\n";
			}
			else{
				AssCode += "\tMOV AX, " + $3->GetSymbolName() + table->GetCurrentScopeID() + "\n";
			}
			AssCode += "\tCALL PRINTLN\n\n";
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    | RETURN expression SEMICOLON
		{
			fprintf(Log, "Line no. %d: statement : RETURN expression SEMICOLON\n\n", LineCount);
			fprintf(Log, "return %s;\n\n", $2->GetSymbolName().c_str());
			
			SymbolInfo* Stat = new SymbolInfo("return " + $2->GetSymbolName() + ";", "statement");
			$$ = Stat;
			if(!ReturnCalled){
				$$->SetCode($2->GetCode());
			}
			ReturnStatementType = $2->GetVariableType();
			struct VariableIdentity ReturnIdentity;
			ReturnIdentity.Name = $2->GetAssemblySymbol();
			if($2->GetIdentity() == "AccessArray"){
				ReturnIdentity.Size = std::to_string($2->GetArrayAccessVariable());
			}
			else{
				ReturnIdentity.Size = "0";
			}
			ReturnExp = ReturnIdentity;
			ReturnCalled = true;
		}
	    ;
	  
expression_statement : SEMICOLON			
		{
			fprintf(Log, "Line no. %d: expression_statement : SEMICOLON\n\n", LineCount);
			fprintf(Log, ";\n\n");
			
			SymbolInfo* Semicolon = new SymbolInfo(";", "expression_statement");
			$$ = Semicolon;
		}
		| expression SEMICOLON 
		{
			fprintf(Log, "Line no. %d: expression_statement : expression SEMICOLON\n\n", LineCount);
			fprintf(Log, "%s;\n\n", $1->GetSymbolName().c_str());
			
			$$ = $1;
			$$->SetSymbolName($1->GetSymbolName() + ";");
			$$->SetSymbolType("expression_statement");
		}
		;
	  
variable : ID 		
		{
			fprintf(Log, "Line no. %d: variable : ID\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			// This nonterminal is used as operand or argument, not for declaration. So, it must be declared before.
			SymbolInfo* Temp = table->LookUp($1->GetSymbolName());
			if(!Temp){
				fprintf(ErrorFile, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				$$->SetVariableType("error");
			}else{
				$$->SetVariableType(Temp->GetVariableType());
				if(Temp->GetVariableType() == "int"){
					$$->IValue = Temp->IValue;
				}else if(Temp->GetVariableType() == "float"){
					$$->FValue = Temp->FValue;
				}
				$$->RetVal = Temp->RetVal;
				$$->GlobalVar = Temp->GlobalVar;
			}
			$$->SetIdentity("Variable");
		}
	    | ID LTHIRD expression RTHIRD 
		{
			fprintf(Log, "Line no. %d: variable : ID LTHIRD expression RTHIRD\n\n", LineCount);
			fprintf(Log, "%s[%s]\n\n", $1->GetSymbolName().c_str(), $3->GetSymbolName().c_str());
			
			SymbolInfo* ArrayVariable = new SymbolInfo($1->GetSymbolName(), "Variable");
			ArrayVariable->SetIdentity("AccessArray");
			
			// Is It Declared?
			SymbolInfo* Temp = table->LookUp($1->GetSymbolName());
			if(!Temp){
				fprintf(ErrorFile, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				ArrayVariable->SetVariableType("error");
			}
			// Is It An Array?
			else if(Temp->GetVariableSize() < 1){
				fprintf(ErrorFile, "Error at Line %d: Subscripted Value(\'%s\') Is Not An Array\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Subscripted Value(\'%s\') Is Not An Array\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				ArrayVariable->SetVariableType("error");
			}
			// Index is undefined variable
			else if($3->GetVariableType() == "error"){
				// Do no printing, the error is already caught
				ArrayVariable->SetVariableType("error");
			}
			// Is The Index An Integer?
			else if($3->GetVariableType() != "int"){
				fprintf(ErrorFile, "Error at Line %d: Array Subscript Is Not An Integer\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Array Subscript Is Not An Integer\n\n", LineCount);
				ErrorCount++;
				ArrayVariable->SetVariableType("error");
			}
			else{
				// Is The Index Within Array Bound?	
				int Index;
				if($3->GetIdentity() == "Variable"){
					Index = $3->IValue;
				}else{
					Index = std::atoi($3->GetSymbolName().c_str());
				}
				if(Index >= Temp->GetVariableSize()){
					fprintf(ErrorFile, "Error at Line %d: Array Index Out Of Bound\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Array Index Out Of Bound\n\n", LineCount);
					ErrorCount++;
					ArrayVariable->SetVariableType("error");
				}
				// Is the index positive?
				else if(Index < 0){
					fprintf(ErrorFile, "Error at Line %d: Array Index Cannot Be Less Than Zero\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Array Index Cannot Be Less Than Zero\n\n", LineCount);
					ErrorCount++;
					ArrayVariable->SetVariableType("error");
				}
				else{
					ArrayVariable->SetArrayAccessVariable(Index);
					ArrayVariable->SetVariableType(Temp->GetVariableType());
					
					if(Temp->GetVariableType() == "int"){
						ArrayVariable->IValue = Temp->IntValue[Index];
					}
					else if(Temp->GetVariableType() == "float"){
						ArrayVariable->FValue = Temp->FloatValue[Index];
					}
					ArrayVariable->RetVal = Temp->RetVal;
				}
			}
			////printf("Var: %s %d\n", $1->GetSymbolName().c_str(), ArrayVariable->GetArrayAccessVariable());
			$$ = ArrayVariable;
		}
	    ;
	 
expression : logic_expression	
		{
			fprintf(Log, "Line no. %d: expression : logic_expression\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("expression");
		}
	    | variable ASSIGNOP logic_expression 	
		{
			fprintf(Log, "Line no. %d: expression : variable ASSIGNOP logic_expression\n\n", LineCount);
			std::string Line = "";
			Line += $1->GetSymbolName();
			if($1->GetIdentity() == "AccessArray"){
				Line+= "[" + std::to_string($1->GetArrayAccessVariable()) + "]";
			}
			Line += " = " + $3->GetSymbolName();
			if($3->GetIdentity() == "AccessArray"){
				Line+= "[" + std::to_string($3->GetArrayAccessVariable()) + "]";
			}
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Exp = new SymbolInfo(Line, "expression");
			$$ = Exp;
			
			// Is The Variable Declared?
			SymbolInfo* Temp = table->LookUp($1->GetSymbolName());
			SymbolInfo* Temp2 = table->LookUp($3->GetSymbolName());
			bool NoErrorFlag = true;
			
			std::string AssCode = $3->GetCode();
			
			if(!Temp){
				// The error should be captured already, So do nothing
			}else{
				Temp->RetVal = $3->RetVal;
				// Is the variable an array (int a[10];) used like a non array (a = 5;)?
				if($1->GetIdentity() != "AccessArray" && Temp->GetIdentity() == "array"){
					fprintf(ErrorFile, "Error at Line %d: Assignment to Expression with Array Type\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Assignment to Expression with Array Type\n\n", LineCount);
					ErrorCount++;
					NoErrorFlag = false;
				}
				// Is the variable a non-array (int a;) used like an array (a[5] = 1)?
				else if($1->GetArrayAccessVariable() >= 0 && Temp->GetIdentity() != "array"){
					fprintf(ErrorFile, "Error at Line %d: Subscripted Value(\'%s\') Is Not An Array\n\n", LineCount, $1->GetSymbolName().c_str());
					fprintf(Log, "Error at Line %d: Subscripted Value(\'%s\') Is Not An Array\n\n", LineCount, $1->GetSymbolName().c_str());
					ErrorCount++;
					NoErrorFlag = false;
				}
				// RVALUE is array type
				else if(Temp2 && Temp2->GetIdentity() == "array" && $3->GetIdentity() != "AccessArray"){
					if($3->GetIdentity() != "Special"){
						fprintf(ErrorFile, "Error at Line %d: Assignment to Expression with Array Type\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Assignment to Expression with Array Type\n\n", LineCount);
						ErrorCount++;
						NoErrorFlag = false;
					}
				}
				else if($3->GetVariableType() != "error" && Temp->GetVariableType() != $3->GetVariableType()){
					if(Temp->GetVariableType() == "float" && $3->GetVariableType() == "int"){}
					else if($3->GetVariableType() != "void"){
						fprintf(ErrorFile, "Error at Line %d: Type Mismatch\n\n", LineCount);
						fprintf(Log, "Error at Line %d: Type Mismatch\n\n", LineCount);
						ErrorCount++;
						NoErrorFlag = false;
					}
				}
				
				if(NoErrorFlag && $1->GetVariableType() != "error" && $3->GetVariableType() != "error"){
					// a[x] = ...
					if(Temp->GetIdentity() == "array"){
						// a[x] = var;
						if(Temp2){
							////printf("%s\n", Temp2->GetSymbolName().c_str());
							// a[x] = b[y];
							if(Temp2->GetIdentity() == "array" && $3->GetIdentity() != "Special"){
								if($1->GetVariableType() == "int"){
									Temp->IntValue[$1->GetArrayAccessVariable()] = Temp2->IntValue[$3->GetArrayAccessVariable()];
								}
								else{
									Temp->FloatValue[$1->GetArrayAccessVariable()] = $3->GetVariableType() == "float"?Temp2->FloatValue[$3->GetArrayAccessVariable()]:Temp2->IntValue[$3->GetArrayAccessVariable()];
								}
								AssCode += "\t;AX = " + $3->GetSymbolName() + "[" + std::to_string($3->GetArrayAccessVariable()) + "]\n";
								AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
								AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
								AssCode += "\tMOV AX, [SI]\n\n";
							}
							// a[x] = b;
							else{
								if($1->GetVariableType() == "int"){
									Temp->IntValue[$1->GetArrayAccessVariable()] = Temp2->IValue;
								}
								else{
									Temp->FloatValue[$1->GetArrayAccessVariable()] = $3->GetVariableType() == "float"?Temp2->FValue:Temp2->IValue;
								}
								AssCode += "\t;AX = " + $3->GetSymbolName() + "\n";
								AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n\n";
							}
						}
						// a[x] = raw value;
						else{
							if($3->GetIdentity() == "Special"){
								AssCode += "\t;AX = " + $3->GetAssemblySymbol() + "\n";
								AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
								Temp->IValue = $3->IValue;
								Temp->FValue = $3->FValue;
							}
							else{
								if($1->GetVariableType() == "int"){
									Temp->IntValue[$1->GetArrayAccessVariable()] = $3->IValue;
									AssCode += "\t;AX = " + std::to_string($3->IValue) + "\n";
									AssCode += "\tMOV AX, " + std::to_string($3->IValue) + "\n\n";
								}
								else{
									Temp->FloatValue[$1->GetArrayAccessVariable()] = $3->GetVariableType() == "float"?$3->FValue:$3->IValue;
								}
							}
						}
						AssCode += "\t;" + $1->GetSymbolName() + "[" + std::to_string($1->GetArrayAccessVariable()) + "] = AX\n";
						AssCode += "\tLEA SI, " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV [SI], AX\n\n";
					}
					else{
						// a = var;
						if(Temp2){
							////printf("%s\n", Temp2->GetSymbolName().c_str());
							// a = b[y];
							if(Temp2->GetIdentity() == "array" && $3->GetIdentity() != "Special"){
								////printf("%s %d\n", $3->GetSymbolName().c_str(), $3->GetArrayAccessVariable());
								if($1->GetVariableType() == "int"){
									Temp->IValue = Temp2->IntValue[$3->GetArrayAccessVariable()];
								}
								else{
									Temp->FValue = $3->GetVariableType() == "float"?Temp2->FloatValue[$3->GetArrayAccessVariable()]:Temp2->IntValue[$3->GetArrayAccessVariable()];
								}
								AssCode += "\t;AX = " + $3->GetSymbolName() + "[" + std::to_string($3->GetArrayAccessVariable()) + "]\n";
								AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
								AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
								AssCode += "\tMOV AX, [SI]\n\n";
							}
							// a = b;
							else{
								if($1->GetVariableType() == "int"){
									Temp->IValue = Temp2->IValue;
								}
								else{
									Temp->FValue = $3->GetVariableType() == "float"?Temp2->FValue:Temp2->IValue;
								}
								AssCode += "\t;AX = " + $3->GetSymbolName() + "\n";
								AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
							}
						}
						// a = raw value;
						else{
							if($3->GetIdentity() == "Special"){
								AssCode += "\t;AX = " + $3->GetAssemblySymbol() + "\n";
								AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
								//printf("%s, %d, %f\n", $3->GetSymbolName().c_str(), $3->IValue, $3->FValue);
								Temp->IValue = $3->IValue;
								Temp->FValue = $3->FValue;
							}
							else{
								if($1->GetVariableType() == "int"){
									Temp->IValue = $3->IValue;
									AssCode += "\t;AX = " + std::to_string($3->IValue) + "\n";
									AssCode += "\tMOV AX, " + std::to_string($3->IValue) + "\n";
								}
								else{
									Temp->FValue = $3->GetVariableType() == "float"?$3->FValue:$3->IValue;
								}
							}
						}
						AssCode += "\t;" + $1->GetSymbolName() + " = AX\n";
						if($1->GlobalVar){
							AssCode += "\tMOV " + $1->GetSymbolName() + "1, AX\n\n";
						}
						else{
							AssCode += "\tMOV " + $1->GetSymbolName() + table->GetCurrentScopeID() + ", AX\n\n";
						}
						
					}
					
				}
			}
			
			if($3->GetVariableType() == "void"){
				fprintf(ErrorFile, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				ErrorCount++;
			}
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
	    ;
			
logic_expression : rel_expression 	
		{
			fprintf(Log, "Line no. %d: logic_expression : rel_expression\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("logic_expression");
		}
		| rel_expression LOGICOP rel_expression 
		{
			fprintf(Log, "Line no. %d: logic_expression : rel_expression LOGICOP rel_expression\n\n", LineCount);
			std::string Line = $1->GetSymbolName() + $2->GetSymbolName() + $3->GetSymbolName();
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Rel = new SymbolInfo(Line, "logic_expression");
			//The result of LOGICOP should be an integer
			Rel->SetVariableType("int");
			
			if($1->GetVariableType() == "void" || $3->GetVariableType() == "void"){
				fprintf(ErrorFile, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				ErrorCount++;
			}
			else{
				int Value;
				
				if($1->GetVariableType() == "int" && $3->GetVariableType() == "int"){
					int First = $1->IValue;
					int Second = $3->IValue;
					
					if($2->GetSymbolName() == "&&") {Value = First && Second;}
					else if($2->GetSymbolName() == "||") {Value = First || Second;}
				}
				else if($1->GetVariableType() == "int" && $3->GetVariableType() == "float"){
					int First = $1->IValue;
					float Second = $3->FValue;
					
					if($2->GetSymbolName() == "&&") {Value = First && Second;}
					else if($2->GetSymbolName() == "||") {Value = First || Second;}
				}
				else if($1->GetVariableType() == "float" && $3->GetVariableType() == "int"){
					float First = $1->FValue;
					int Second = $3->IValue;
					
					if($2->GetSymbolName() == "&&") {Value = First && Second;}
					else if($2->GetSymbolName() == "||") {Value = First || Second;}
				}
				else if($1->GetVariableType() == "float" && $3->GetVariableType() == "float"){
					float First = $1->FValue;
					float Second = $3->FValue;
					
					if($2->GetSymbolName() == "&&") {Value = First && Second;}
					else if($2->GetSymbolName() == "||") {Value = First || Second;}
				}
				
				Rel->IValue = Value;
			}
			
			std::string Falmse = NewLabel();
			std::string DoneLabel = NewLabel();
			std::string Temp = NewTemp();
			std::string AssCode = $1->GetCode() + $3->GetCode();
			AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
			//AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
			if($1->GetIdentity() == "AccessArray"){
				AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
				AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
				AssCode += "\tMOV AX, [SI]\n\n";
			}
			else{
				AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
			}
			//AssCode += "\tMOV DX, " + $3->GetAssemblySymbol() + "\n";
			if($3->GetIdentity() == "AccessArray"){
				AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
				AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
				AssCode += "\tMOV DX, [SI]\n\n";
			}
			else{
				AssCode += "\tMOV DX, " + $3->GetAssemblySymbol() + "\n";
			}
			
			if($2->GetSymbolName() == "&&"){
				AssCode += "\tCMP AX, 0\n";
				AssCode += "\tJE " + Falmse + "\n";
				AssCode += "\tCMP DX, 0\n";
				AssCode += "\tJE " + Falmse + "\n";
				AssCode += "\tMOV AX, 1\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += Falmse + ":\n";
				AssCode += "\tMOV AX, 0\n";
			}
			else{
				AssCode += "\tCMP AX, 0\n";
				AssCode += "\tJNE " + Falmse + "\n";
				AssCode += "\tCMP DX, 0\n";
				AssCode += "\tJNE " + Falmse + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += Falmse + ":\n";
				AssCode += "\tMOV AX, 1\n";
			}
			AssCode += DoneLabel + ":\n";
			AssCode += "\tMOV " + Temp + ", AX\n\n";
			
			$$ = Rel;
			$$->RetVal = $1->RetVal || $3->RetVal;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$$->SetAssemblySymbol(Temp);
			$$->SetIdentity("Special");
		}	
		;
			
rel_expression	: simple_expression 
		{
			fprintf(Log, "Line no. %d: rel_expression : simple_expression\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("rel_expression");
		}
		| simple_expression RELOP simple_expression	
		{
			fprintf(Log, "Line no. %d: rel_expression : simple_expression RELOP simple_expression\n\n", LineCount);
			std::string Line = $1->GetSymbolName() + $2->GetSymbolName() + $3->GetSymbolName();
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Rel = new SymbolInfo(Line, "rel_expression");
			//The result of RELOP should be an integer
			Rel->SetVariableType("int");
			
			if($1->GetVariableType() == "void" || $3->GetVariableType() == "void"){
				fprintf(ErrorFile, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				ErrorCount++;
			}
			else{
				int Value;
				if($1->GetVariableType() == "int" && $3->GetVariableType() == "int"){
					int First = $1->IValue;
					int Second = $3->IValue;
					
					if($2->GetSymbolName() == ">") {Value = First > Second;}
					else if($2->GetSymbolName() == "<") {Value = First < Second;}
					else if($2->GetSymbolName() == ">=") {Value = First >= Second;}
					else if($2->GetSymbolName() == "<=") {Value = First <= Second;}
					else if($2->GetSymbolName() == "==") {Value = First == Second;}
					else if($2->GetSymbolName() == "!=") {Value = First != Second;}
				}
				else if($1->GetVariableType() == "int" && $3->GetVariableType() == "float"){
					int First = $1->IValue;
					float Second = $3->FValue;
				
					if($2->GetSymbolName() == ">") {Value = First > Second;}
					else if($2->GetSymbolName() == "<") {Value = First < Second;}
					else if($2->GetSymbolName() == ">=") {Value = First >= Second;}
					else if($2->GetSymbolName() == "<=") {Value = First <= Second;}
					else if($2->GetSymbolName() == "==") {Value = First == Second;}
					else if($2->GetSymbolName() == "!=") {Value = First != Second;}
				}
				else if($1->GetVariableType() == "float" && $3->GetVariableType() == "int"){
					float First = $1->FValue;
					int Second = $3->IValue;
				
					if($2->GetSymbolName() == ">") {Value = First > Second;}
					else if($2->GetSymbolName() == "<") {Value = First < Second;}
					else if($2->GetSymbolName() == ">=") {Value = First >= Second;}
					else if($2->GetSymbolName() == "<=") {Value = First <= Second;}
					else if($2->GetSymbolName() == "==") {Value = First == Second;}
					else if($2->GetSymbolName() == "!=") {Value = First != Second;}
				}
				else if($1->GetVariableType() == "float" && $3->GetVariableType() == "float"){
					float First = $1->FValue;
					float Second = $3->FValue;
				
					if($2->GetSymbolName() == ">") {Value = First > Second;}
					else if($2->GetSymbolName() == "<") {Value = First < Second;}
					else if($2->GetSymbolName() == ">=") {Value = First >= Second;}
					else if($2->GetSymbolName() == "<=") {Value = First <= Second;}
					else if($2->GetSymbolName() == "==") {Value = First == Second;}
					else if($2->GetSymbolName() == "!=") {Value = First != Second;}
				}
				Rel->IValue = Value;
			}
			
			std::string AssCode = $1->GetCode() + $3->GetCode();
			AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
			std::string Temp = NewTemp();
			std::string CodeLabel = NewLabel();
			std::string DoneLabel = NewLabel();
			//AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
			if($1->GetIdentity() == "AccessArray"){
				AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
				AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
				AssCode += "\tMOV AX, [SI]\n\n";
			}
			else{
				AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
			}
			
			if($3->GetIdentity() == "AccessArray"){
				AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
				AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
				AssCode += "\tMOV DX, [SI]\n\n";
			}
			else{
				AssCode += "\tMOV DX, " + $3->GetAssemblySymbol() + "\n";
			}
			
			AssCode += "\tCMP AX, DX\n";
			
			if($2->GetSymbolName() == ">") {
				AssCode += "\tJG " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else if($2->GetSymbolName() == "<") {
				AssCode += "\tJL " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else if($2->GetSymbolName() == ">=") {
				AssCode += "\tJGE " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else if($2->GetSymbolName() == "<=") {
				AssCode += "\tJLE " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else if($2->GetSymbolName() == "==") {
				AssCode += "\tJE " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else if($2->GetSymbolName() == "!=") {
				AssCode += "\tJNE " + CodeLabel + "\n";
				AssCode += "\tMOV AX, 0\n";
				AssCode += "\tJMP " + DoneLabel + "\n";
				AssCode += CodeLabel + ":\n"; 
				AssCode += "\tMOV AX, 1\n";
				AssCode += DoneLabel + ":\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			
			$$ = Rel;
			$$->RetVal = $1->RetVal || $3->RetVal;
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$$->SetAssemblySymbol(Temp);
			$$->SetIdentity("Special");
		}
		;
				
simple_expression : term 
		{
			fprintf(Log, "Line no. %d: simple_expression : term\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("simple_expression");
		}
		| simple_expression ADDOP term 
		{
			fprintf(Log, "Line no. %d: simple_expression : simple_expression ADDOP term\n\n", LineCount);
			std::string Line = $1->GetSymbolName() + $2->GetSymbolName() + $3->GetSymbolName();
			fprintf(Log, "%s\n\n", Line.c_str());
			SymbolInfo* Simp = new SymbolInfo(Line, "simple_expression");
			if($1->GetVariableType() == "float" || $3->GetVariableType() == "float"){
				Simp->SetVariableType("float");
				float First = $1->GetVariableType() == "float"?$1->FValue:$1->IValue;
				float Second = $3->GetVariableType() == "float"?$3->FValue:$3->IValue;
				if($2->GetSymbolName() == "+"){
					Simp->FValue = First + Second;
				}
				else if($2->GetSymbolName() == "-"){
					Simp->FValue = First - Second;
				}
			}
			else if($1->GetVariableType() == "void" || $3->GetVariableType() == "void"){
				fprintf(ErrorFile, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				fprintf(Log, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
				ErrorCount++;
				Simp->SetVariableType("error");
			}
			else if($1->GetVariableType() == "error"){
				Simp->SetVariableType($3->GetVariableType());
			}
			else if($3->GetVariableType() == "error"){
				Simp->SetVariableType($1->GetVariableType());
			}
			else{
				Simp->SetVariableType("int");
				int First = $1->IValue;
				int Second = $3->IValue;
				if($2->GetSymbolName() == "+"){
					Simp->FValue = First + Second;
				}
				else if($2->GetSymbolName() == "-"){
					Simp->FValue = First - Second;
				}
			}
			$$ = Simp;
			$$->RetVal = $1->RetVal || $3->RetVal;
			
			std::string AssCode = $1->GetCode() + $3->GetCode();
			AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
			std::string Temp = NewTemp();
			if($2->GetSymbolName() == "+"){
				if($3->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV AX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV AX, " + $3->GetAssemblySymbol() + "\n";
				}
				if($1->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV DX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV DX, " + $1->GetAssemblySymbol() + "\n";
				}
				AssCode += "\tADD AX, DX\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			else{
				if($1->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV AX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
				}
				if($3->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV DX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV DX, " + $3->GetAssemblySymbol() + "\n";
				}
				AssCode += "\tSUB AX, DX\n";
				AssCode += "\tMOV " + Temp + ", AX\n\n";
			}
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$$->SetAssemblySymbol(Temp);
			$$->SetIdentity("Special");
		}
		;
					
term :	unary_expression
		{
			fprintf(Log, "Line no. %d: term : unary_expression\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("term");
		}
     	|  term MULOP unary_expression
		{
			fprintf(Log, "Line no. %d: term : unary_expression\n\n", LineCount);
			std::string Line = $1->GetSymbolName() + $2->GetSymbolName() + $3->GetSymbolName();
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Sym = new SymbolInfo(Line, "term");
			Sym->RetVal = $3->RetVal || $1->RetVal;
			std::string AssCode = $1->GetCode() + $3->GetCode();
			std::string Temp = NewTemp();
			
			// MULOP has the operator %. It only works on two integers on C and C++
			if($2->GetSymbolName() == "%"){
				Sym->SetVariableType("int");
				if($1->GetVariableType() != "int" || $3->GetVariableType() != "int"){
					fprintf(ErrorFile, "Error at Line %d: Invalid Operands To Binary %(Have \'%s\' and \'%s\')\n\n", LineCount, $1->GetVariableType().c_str(), $3->GetVariableType().c_str());
					fprintf(Log, "Error at Line %d: Invalid Operands To Binary %(Have \'%s\' and \'%s\')\n\n", LineCount, $1->GetVariableType().c_str(), $3->GetVariableType().c_str());
					ErrorCount++;
				}else{
					if($3->GetIdentity() == "Variable"){
						int Op = $3->IValue;
						if(Op==0 && !$3->RetVal){
							fprintf(ErrorFile, "Error at Line %d: Modulus By Zero\n\n", LineCount);
							fprintf(Log, "Error at Line %d: Modulus By Zero\n\n", LineCount);
							ErrorCount++;
						}
					}
					else if($3->GetIdentity() == "AccessArray"){
						// Should Check
					}
					else{
						int Op = std::atoi($3->GetSymbolName().c_str());
						if(Op == 0 && !$3->RetVal){
							fprintf(ErrorFile, "Error at Line %d: Modulus By Zero\n\n", LineCount);
							fprintf(Log, "Error at Line %d: Modulus By Zero\n\n", LineCount);
							ErrorCount++;
						}
					}
				}
				AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
				AssCode += "\tMOV DX, 0\n";
				if($1->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV AX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
				}
				AssCode += "\tCWD\n";
				if($3->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV CX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV CX, " + $3->GetAssemblySymbol() + "\n";
				}
				AssCode += "\tIDIV CX\n";
				AssCode += "\tMOV " + Temp + ", DX\n\n";
			}else{
				// If any one of the operands is float, the result is a float
				if($1->GetVariableType() == "float" || $3->GetVariableType() == "float"){
					Sym->SetVariableType("float");
					float First = $1->GetVariableType() == "float"?$1->FValue:$1->IValue;
					float Second = $3->GetVariableType() == "float"?$3->FValue:$3->IValue;
					if($2->GetSymbolName() == "*"){
						if($1->RetVal || $3->RetVal){}
						else Sym->FValue = First * Second;
					}
					else if($2->GetSymbolName() == "/"){
						if(Second == 0 && !$3->RetVal){
							fprintf(ErrorFile, "Error at Line %d: Division By Zero\n\n", LineCount);
							fprintf(Log, "Error at Line %d: Division By Zero\n\n", LineCount);
							ErrorCount++;
						}
						else{
							if($1->RetVal || $3->RetVal){
							}
							else{
								Sym->FValue = First / Second;
							}
						}
					}
				}
				// No void operations allowed
				else if($1->GetVariableType() == "void" || $3->GetVariableType() == "void"){
					fprintf(ErrorFile, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
					fprintf(Log, "Error at Line %d: Void Value Not Ignored As It Ought To Be\n\n", LineCount);
					ErrorCount++;
					Sym->SetVariableType("error");
				}
				else if($1->GetVariableType() == "error"){
					Sym->SetVariableType($3->GetVariableType());
				}
				else if($3->GetVariableType() == "error"){
					Sym->SetVariableType($1->GetVariableType());
				}
				else{
					//printf("%s %s\n", $1->GetSymbolName().c_str(), $3->GetSymbolName().c_str());
					Sym->SetVariableType("int");
					
					int First = $1->IValue;
					int Second = $3->IValue;
					//printf("%d %d\n", First, Second);
					if($2->GetSymbolName() == "*"){
						if($1->RetVal || $3->RetVal){}
						else Sym->IValue = First * Second;
					}
					else if($2->GetSymbolName() == "/"){
						if(Second == 0  && !$3->RetVal){
							fprintf(ErrorFile, "Error at Line %d: Division By Zero\n\n", LineCount);
							fprintf(Log, "Error at Line %d: Division By Zero\n\n", LineCount);
							ErrorCount++;
						}
						else{
							if($1->RetVal || $3->RetVal){
							}
							else{
								Sym->IValue = First / Second;
							}
						}
					}
				}
				
				if($2->GetSymbolName() == "/"){
					AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
					AssCode += "\tMOV DX, 0\n";
					if($1->GetIdentity() == "AccessArray"){
						AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
						AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV AX, [SI]\n\n";
					}
					else{
						AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
					}
					AssCode += "\tCWD\n";
					if($3->GetIdentity() == "AccessArray"){
						AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
						AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV CX, [SI]\n\n";
					}
					else{
						AssCode += "\tMOV CX, " + $3->GetAssemblySymbol() + "\n";
					}
					AssCode += "\tIDIV CX\n";
					AssCode += "\tMOV " + Temp + ", AX\n\n";
				}
				else{
					AssCode += "\t;" + $1->GetAssemblySymbol() + $2->GetSymbolName() + $3->GetAssemblySymbol() + "\n";
					if($1->GetIdentity() == "AccessArray"){
						AssCode += "\tLEA SI, " + $1->GetAssemblySymbol() + "\n";
						AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV AX, [SI]\n\n";
					}
					else{
						AssCode += "\tMOV AX, " + $1->GetAssemblySymbol() + "\n";
					}
					if($3->GetIdentity() == "AccessArray"){
						AssCode += "\tLEA SI, " + $3->GetAssemblySymbol() + "\n";
						AssCode += "\tADD SI, " + std::to_string($3->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV DX, [SI]\n\n";
					}
					else{
						AssCode += "\tMOV DX, " + $3->GetAssemblySymbol() + "\n";
					}
					AssCode += "\tIMUL DX\n";
					AssCode += "\tMOV " + Temp + ", AX\n\n";
				}
			}
			$$ = Sym;
			$$->SetIdentity("Special");
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$$->SetAssemblySymbol(Temp);
		}
     	;

unary_expression : ADDOP unary_expression
		{
			fprintf(Log, "Line no. %d: unary_expression : ADDOP unary_expression\n\n", LineCount);
			std::string Expr = $1->GetSymbolName() + $2->GetSymbolName();
			fprintf(Log, "%s\n\n", Expr.c_str());
			
			//SymbolInfo* Exp = new SymbolInfo(Expr, "unary_expression");
			//Exp->SetVariableType($2->GetVariableType());
			$$ = $2;
			$$->SetSymbolName(Expr);
			$$->SetSymbolType("unary_expression");
			
			std::string AssCode = $2->GetCode();
			
			if($1->GetSymbolName() == "+"){
				$$->SetAssemblySymbol($2->GetAssemblySymbol());
				$$->SetIdentity($2->GetIdentity());
			}
			else if($1->GetSymbolName() == "-"){
				$$->IValue = -$$->IValue;
				$$->FValue = -$$->FValue;
				
				std::string Temp = NewTemp();
				AssCode += "\t;" + Temp + " = " + Expr + "\n";
				if($2->GetIdentity() == "AccessArray"){
					AssCode += "\tLEA SI, " + $2->GetAssemblySymbol() + "\n";
					AssCode += "\tADD SI, " + std::to_string($2->GetArrayAccessVariable()) + "*2\n";
					AssCode += "\tMOV AX, [SI]\n\n";
				}
				else{
					AssCode += "\tMOV AX, " + $2->GetAssemblySymbol() + "\n";
				}
				AssCode += "\tMOV " + Temp + ", AX\n";
				AssCode += "\tNEG " + Temp + "\n\n";
				
				$$->SetAssemblySymbol(Temp);
				$$->SetIdentity("Special");
			}
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
		}
		| NOT unary_expression 
		{
			fprintf(Log, "Line no. %d: unary_expression : NOT unary_expression\n\n", LineCount);
			std::string Expr = "!" + $2->GetSymbolName();
			fprintf(Log, "%s\n\n", Expr.c_str());
			
			SymbolInfo* Exp = new SymbolInfo(Expr, "unary_expression");
			Exp->SetVariableType("int");
			Exp->RetVal = $2->RetVal;
			$$ = Exp;
			if($2->GetVariableType() == "int"){
				$$->IValue = !$2->IValue;
			}
			else if($2->GetVariableType() == "float"){
				$$->IValue = !$2->FValue;
			}
			
			std::string AssCode = $2->GetCode();
			std::string ZeroLabel = NewLabel();
			std::string DoneLabel = NewLabel();
			std::string Temp = NewTemp();
			
			AssCode += "\t;!" + $2->GetAssemblySymbol() + "\n";
			if($2->GetIdentity() == "AccessArray"){
				AssCode += "\tLEA SI, " + $2->GetAssemblySymbol() + "\n";
				AssCode += "\tADD SI, " + std::to_string($2->GetArrayAccessVariable()) + "*2\n";
				AssCode += "\tMOV AX, [SI]\n\n";
			}
			else{
				AssCode += "\tMOV AX, " + $2->GetAssemblySymbol() + "\n";
			}
			AssCode += "\tCMP AX , 0\n";
			AssCode += "\tJZ " + ZeroLabel + "\n";
			AssCode += "\tMOV AX, 0\n";
			AssCode += "\tMOV " + Temp + ", AX\n";
			AssCode += "\tJMP " + DoneLabel + "\n\n";
			
			AssCode += ZeroLabel + ":\n";
			AssCode += "\tMOV AX, 1\n";
			AssCode += "\tMOV " + Temp + ", AX\n\n";
			
			AssCode += DoneLabel + ":\n";
			
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$$->SetAssemblySymbol(Temp);
			$$->SetIdentity("Special");
		} 
		| factor 
		{
			fprintf(Log, "Line no. %d: unary_expression : factor\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetSymbolType("unary_expression");
		}
		;
	
factor	: variable
		{
			fprintf(Log, "Line no. %d: factor : variable\n\n", LineCount);
			std::string Line = $1->GetSymbolName();
			std::string Line2 = Line;
			if($1->GetIdentity() == "AccessArray"){
				Line+= "[" + std::to_string($1->GetArrayAccessVariable()) + "]";
			}
			fprintf(Log, "%s\n\n", Line.c_str());
			SymbolInfo* Fac = new SymbolInfo(Line2, "factor");
			
			Fac->SetVariableType($1->GetVariableType());
			Fac->SetIdentity($1->GetIdentity());
			Fac->SetArrayAccessVariable($1->GetArrayAccessVariable());
			if($1->GlobalVar){
				Fac->SetAssemblySymbol($1->GetSymbolName() + "1");
			}else{
				Fac->SetAssemblySymbol($1->GetSymbolName() + table->GetCurrentScopeID());
			}
			Fac->GlobalVar = $1->GlobalVar;
			
			////printf("Factor: %s %d\n", $1->GetSymbolName().c_str(), Fac->GetArrayAccessVariable());
			
			if(Fac->GetVariableType() == "int"){
				Fac->IValue = $1->IValue;
			}
			else if(Fac->GetVariableType() == "float"){
				Fac->FValue = $1->FValue;
			}
			Fac->RetVal = $1->RetVal;
			$$ = Fac;
		} 
		| ID LPAREN argument_list RPAREN
		{
			fprintf(Log, "Line no. %d: factor : ID LPAREN argument_list RPAREN\n\n", LineCount);
			
			std::string Line = $1->GetSymbolName() + "(";
			for(int Counter = 0; Counter < $3->ParamList.size(); Counter++){
				Line += $3->ParamList[Counter]->GetSymbolName();
				if(Counter != $3->ParamList.size() - 1){
					Line += ", ";
				}
			}
			Line += ")";
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Func = new SymbolInfo(Line, "factor");
			$$ = Func;
			std::string AssCode = "";
			AssCode += "\t;" + Line + "\n";
			AssCode += "\tPUSH ADDRESS\n";
			// Foo(a,b,c) -> Check for function call
			SymbolInfo* Fun = table->LookUp($1->GetSymbolName());
			
			if(Fun){
				// Function found, so the factor type should be the the type which the function returns
				$$->SetVariableType(Fun->GetReturnType());
				$$->RetVal = true;
			}else{
				// Function not found
				$$->SetVariableType("error");
				fprintf(ErrorFile, "Error at Line %d: Undeclared Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Undeclared Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
			}
			
			// Function not defined, or the name does not belong to a function
			if(Fun && (Fun->GetIdentity() != "function_definition" && Fun->GetIdentity() != "func_declaration")){
				fprintf(ErrorFile, "Error at Line %d: Undefined Reference to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Undefined Reference to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				$$->SetVariableType("error");
			}
			// Argument counts do not match
			else if(Fun && Fun->ParamList.size() > $3->ParamList.size()){
				fprintf(ErrorFile, "Error at Line %d: Too Few Arguments to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Too Few Arguments to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				$$->SetVariableType("error");
			}
			else if(Fun && Fun->ParamList.size() < $3->ParamList.size()){
				fprintf(ErrorFile, "Error at Line %d: Too Many Arguments to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				fprintf(Log, "Error at Line %d: Too Many Arguments to Function \'%s\'\n\n", LineCount, $1->GetSymbolName().c_str());
				ErrorCount++;
				$$->SetVariableType("error");
			}
			// Function defined, argument counts match
			else if(Fun){
				////printf("%s %d\n", Fun->GetSymbolName().c_str(), $3->ParamList.size());
				// Arguments can be both variables or Values
				for(int Counter = 0; Counter < $3->ParamList.size(); Counter++){
					SymbolInfo* Temp = table->LookUp($3->ParamList[Counter]->GetSymbolName());
					// In case its a declared variable
					if(Temp){
						// Variable types did not match
						if(Temp->GetVariableType() != Fun->ParamList[Counter]->GetVariableType() || Temp->GetVariableSize() != Fun->ParamList[Counter]->GetVariableSize()){
							if(Fun->ParamList[Counter]->GetVariableType() == "float" && Temp->GetVariableType() == "int" && Temp->GetVariableSize() == Fun->ParamList[Counter]->GetVariableSize()){
								AssCode += "\tMOV AX, " + $3->ParamList[Counter]->GetSymbolName() + table->GetCurrentScopeID() + "\n";
								AssCode += "\tMOV " + Fun->ParamList[Counter]->GetSymbolName() + Fun->GetImplementationID() + ", AX\n";
							}
							else{
								fprintf(ErrorFile, "Error at Line %d: Incompatible Type for Argument %d of \'%s\'\n\n", LineCount, Counter + 1, $1->GetSymbolName().c_str());
								fprintf(Log, "Error at Line %d: Incompatible Type for Argument %d of \'%s\'\n\n", LineCount, Counter + 1, $1->GetSymbolName().c_str());
								ErrorCount++;
								$$->SetVariableType("error");
								break;
							}
						}
						else{
							//AssCode += "\tMOV AX, " + $3->ParamList[Counter]->GetSymbolName() + table->GetCurrentScopeID() + "\n";
							//AssCode += "\tMOV " + Fun->ParamList[Counter]->GetSymbolName() + Fun->GetImplementationID() + ", AX\n";
							AssCode += "\tPUSH " + $3->ParamList[Counter]->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						}
					}
					
					// In Case its a value, not a variable. In this case, as defined, it will have no special identity, unlike defined variables, who have "Variable" identity
					// If the identity is "Variable", that means the variable is not declared, since it is not in the Symbol Table
					else if($3->ParamList[Counter]->GetIdentity() == "Variable"){
						if($3->ParamList[Counter]->GetVariableType() == "error"){}
						else{
							fprintf(ErrorFile, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $3->ParamList[Counter]->GetSymbolName().c_str());
							fprintf(Log, "Error at Line %d: \'%s\' Undeclared\n\n", LineCount, $3->ParamList[Counter]->GetSymbolName().c_str());
							ErrorCount++;
							$$->SetVariableType("error");
							break;
						}
					}
					else if($3->ParamList[Counter]->GetVariableType() != Fun->ParamList[Counter]->GetVariableType()){
						if(Fun->ParamList[Counter]->GetVariableType() == "float" && $3->ParamList[Counter]->GetVariableType() == "int"){
							//AssCode += "\tMOV " + Fun->ParamList[Counter]->GetSymbolName() + Fun->GetImplementationID() + ", " + $3->ParamList[Counter]->GetSymbolName() + "\n";
							AssCode += "\tPUSH" + $3->ParamList[Counter]->GetSymbolName() + "\n";
						}
						else{
							fprintf(ErrorFile, "Error at Line %d: Incompatible Type for Argument %d of \'%s\'\n\n", LineCount, Counter + 1, $1->GetSymbolName().c_str());
							fprintf(Log, "Error at Line %d: Incompatible Type for Argument %d of \'%s\'\n\n", LineCount, Counter + 1, $1->GetSymbolName().c_str());
							ErrorCount++;
							$$->SetVariableType("error");
							break;
						}
					}
					else{
						//AssCode += "\tMOV " + Fun->ParamList[Counter]->GetSymbolName() + Fun->GetImplementationID() + ", " + $3->ParamList[Counter]->GetSymbolName() + "\n";
						AssCode += "\tPUSH " + $3->ParamList[Counter]->GetSymbolName() + "\n";
					}
				}
				AssCode += "\tCALL " + $1->GetSymbolName() + "\n\n";
				if(Fun->GetReturnType() != "void"){
					AssCode += "\t;Restore Address & Store The Return Value\n";
					std::string Temp = NewTemp();
					AssCode += "\tPOP " + Temp + "\n";
					AssCode += "\tPOP ADDRESS\n\n";
					$$->SetAssemblySymbol(Temp);
					$$->SetIdentity("Special");
				}
			}
			if(!ReturnCalled){
				$$->SetCode(AssCode);
			}
			$3->ParamList.clear();
		}
		| LPAREN expression RPAREN
		{
			fprintf(Log, "Line no. %d: factor : LPAREN expression RPAREN\n\n", LineCount);
			
			std::string Line = "(" + $2->GetSymbolName() + ")";
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Exp = new SymbolInfo(Line, "factor");
			// The new type after operation will remain the same as the old type
			Exp->SetVariableType($2->GetVariableType());
			if($2->GetVariableType() == "int"){
				Exp->IValue = $2->IValue;
			}
			else if($2->GetVariableType() == "float"){
				Exp->FValue = $2->FValue;
			}
			$$ = Exp;
			$$->SetCode($2->GetCode());
			$$->SetAssemblySymbol($$->GetSymbolName());
			$$->RetVal = $2->RetVal;
		}
		| CONST_INT 
		{
			fprintf(Log, "Line no. %d: factor : CONST_INT\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetVariableType("int");
			$$->SetSymbolType("factor");
			$$->IValue = std::atoi($1->GetSymbolName().c_str());
			$$->SetAssemblySymbol($1->GetSymbolName());
		}
		| CONST_FLOAT
		{
			fprintf(Log, "Line no. %d: factor : CONST_FLOAT\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			$$ = $1;
			$$->SetVariableType("float");
			$$->SetSymbolType("factor");
			$$->FValue = std::atof($1->GetSymbolName().c_str());
			$$->SetAssemblySymbol($1->GetSymbolName());
		}
		| variable INCOP 
		{
			fprintf(Log, "Line no. %d: factor : variable INCOP\n\n", LineCount);
			std::string Line = $1->GetSymbolName();
			if($1->GetIdentity() == "AccessArray"){
				Line+= "[" + std::to_string($1->GetArrayAccessVariable()) + "]";
			}
			Line += "++";
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Inc = new SymbolInfo($1->GetSymbolName(), "factor");
			Inc->SetVariableType($1->GetVariableType());
			$$ = Inc;
			
			SymbolInfo* Temp = table->LookUp($1->GetSymbolName());
			std::string AssCode = "";
			if(Temp){
				std::string TempVar = NewTemp();
				if(Temp->GetVariableType() == "int"){
					if($1->GetIdentity() == "AccessArray"){
						$$->IValue = Temp->IntValue[$1->GetArrayAccessVariable()];
						Temp->IntValue[$1->GetArrayAccessVariable()]++;
						
						AssCode += "\t;Variable INCOP\n";
						AssCode += "\tLEA SI, " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV AX, [SI]\n";
						AssCode += "\tMOV " + TempVar + ", AX\n";
						AssCode += "\tINC [SI]\n\n";
					}
					else if($1->GetIdentity() == "Variable"){
						$$->IValue = Temp->IValue;
						Temp->IValue++;
						
						AssCode += "\t;Variable INCOP\n";
						AssCode += "\tMOV AX, " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						AssCode += "\tMOV " + TempVar + ", AX\n";
						AssCode += "\tINC " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n\n";
					}
				}
				else if(Temp->GetVariableType() == "float"){
					if($1->GetIdentity() == "AccessArray"){
						$$->FValue = Temp->FloatValue[$1->GetArrayAccessVariable()];
						Temp->FloatValue[$1->GetArrayAccessVariable()]++;
					}
					else if($1->GetIdentity() == "Variable"){
						$$->FValue = Temp->FValue;
						Temp->FValue++;
					}
				}
				$$->SetIdentity("Special");
				if(!ReturnCalled){
					$$->SetCode(AssCode);
				}
				$$->SetAssemblySymbol(TempVar);
			}
		}
		| variable DECOP
		{
			fprintf(Log, "Line no. %d: factor : variable DECOP\n\n", LineCount);
			std::string Line = $1->GetSymbolName();
			if($1->GetIdentity() == "AccessArray"){
				Line+= "[" + std::to_string($1->GetArrayAccessVariable()) + "]";
			}
			Line += "--";
			fprintf(Log, "%s\n\n", Line.c_str());
			
			SymbolInfo* Dec = new SymbolInfo($1->GetSymbolName(), "factor");
			// The new type after operation will remain the same as the old type
			Dec->SetVariableType($1->GetVariableType());
			$$ = Dec;
			
			SymbolInfo* Temp = table->LookUp($1->GetSymbolName());
			std::string AssCode = "";
			if(Temp){
				////printf("%s\n", $1->GetSymbolName().c_str());
				std::string TempVar = NewTemp();
				
				if(Temp->GetVariableType() == "int"){
					if($1->GetIdentity() == "AccessArray"){
						$$->IValue = Temp->IntValue[$1->GetArrayAccessVariable()];
						Temp->IntValue[$1->GetArrayAccessVariable()]--;
						
						AssCode += "\t;Variable DECOP\n";
						AssCode += "\tLEA SI, " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						AssCode += "\tADD SI, " + std::to_string($1->GetArrayAccessVariable()) + "*2\n";
						AssCode += "\tMOV AX, [SI]\n";
						AssCode += "\tMOV " + TempVar + ", AX\n";
						AssCode += "\tDEC [SI]\n\n";
					}
					else if($1->GetIdentity() == "Variable"){
						$$->IValue = Temp->IValue;
						Temp->IValue--;
						
						AssCode += "\t;Variable DECOP\n";
						AssCode += "\tMOV AX, " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n";
						AssCode += "\tMOV " + TempVar + ", AX\n";
						AssCode += "\tDEC " + $1->GetSymbolName() + table->GetCurrentScopeID() + "\n\n";
					}
				}
				else if(Temp->GetVariableType() == "float"){
					if($1->GetIdentity() == "AccessArray"){
						$$->FValue = Temp->FloatValue[$1->GetArrayAccessVariable()];
						Temp->FloatValue[$1->GetArrayAccessVariable()]--;
					}
					else if($1->GetIdentity() == "Variable"){
						$$->FValue = Temp->FValue;
						Temp->FValue--;
					}
				}
				$$->SetIdentity("Special");
				if(!ReturnCalled){
					$$->SetCode(AssCode);
				}
				$$->SetAssemblySymbol(TempVar);
			}
		}
		;
	
argument_list : arguments
		{
			fprintf(Log, "Line no. %d: argument_list : arguments\n\n", LineCount);
			for(int Counter = 0; Counter < $1->ParamList.size(); Counter++){
				fprintf(Log, "%s", $1->ParamList[Counter]->GetSymbolName().c_str());
				if(Counter != $1->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			fprintf(Log, "\n\n");
			$$ = $1;
			$$->SetSymbolType("argument_list");
		}
		|
		{
			fprintf(Log, "Line no. %d: argument_list : \n\n", LineCount);
			SymbolInfo* ArgNew = new SymbolInfo("", "argument_list");
			$$ = ArgNew;
		}
 	    ;
	
arguments : arguments COMMA logic_expression
		{
			fprintf(Log, "Line no. %d: arguments : arguments COMMA logic_expression\n\n", LineCount);
			SymbolInfo* Arg = new SymbolInfo($3->GetSymbolName(), "arguments");
			Arg->SetVariableType($3->GetVariableType());
			Arg->SetIdentity($3->GetIdentity());
			Arg->IValue = $3->IValue;
			Arg->FValue = $3->FValue;
			$$ = $1;
			$$->ParamList.push_back(Arg);
			$$->SetCode($1->GetCode() + $3->GetCode());
			for(int Counter = 0; Counter < $1->ParamList.size(); Counter++){
				fprintf(Log, "%s", $1->ParamList[Counter]->GetSymbolName().c_str());
				if(Counter != $1->ParamList.size() - 1){
					fprintf(Log, ", ");
				}
			}
			fprintf(Log, "\n\n");
		}
	    | logic_expression
		{
			fprintf(Log, "Line no. %d: arguments : logic_expression\n\n", LineCount);
			fprintf(Log, "%s\n\n", $1->GetSymbolName().c_str());
			
			SymbolInfo* Args = new SymbolInfo("ArgList");
			SymbolInfo* Arg = new SymbolInfo($1->GetSymbolName(), "arguments");
			Arg->SetVariableType($1->GetVariableType());
			Arg->SetIdentity($1->GetIdentity());
			Arg->IValue = $1->IValue;
			Arg->FValue = $1->FValue;
			Arg->SetCode($1->GetCode());
			Args->ParamList.push_back(Arg);
			$$ = Args;
		}
	    ;
 

%%
int main(int argc,char *argv[])
{
	if((yyin=fopen(argv[1],"r"))==NULL)
	{
		printf("Cannot Open Input File.\n");
		//yyin=fopen("input.txt","r");
		exit(1);
	}

	Log = fopen("1705058_Log.txt", "w");
	ErrorFile = fopen("1705058_Error.txt", "w");
	Assembly = fopen("code.asm", "w");
	Optimized = fopen("optimized_code.asm", "w");
	fclose(Log);
	fclose(ErrorFile);
	fclose(Assembly);
	fclose(Optimized);
		
	Log = fopen("1705058_Log.txt", "a");
	ErrorFile = fopen("1705058_Error.txt", "a");
	Assembly = fopen("code.asm", "a");
	Optimized = fopen("optimized_code.asm", "a");
	

	yyparse();
	
	// Print the stats
	fprintf(Log, "Symbol Table:\n\n");
	table->PrintAllScopes(Log);
	fprintf(Log, "\n\n");
	fprintf(Log, "Total Lines: %d\n\n", LineCount-1);
	fprintf(Log, "Total Errors: %d\n\n", ErrorCount);
	fprintf(ErrorFile, "\n\nTotal Errors: %d\n\n", ErrorCount);
	
	fclose(Log);
	fclose(ErrorFile);
	fclose(Assembly);
	
	Assembly = fopen("code.asm", "r");
	
	if(ErrorCount == 0){
		OptimizeCode(GetAssemblyCode());
	}
	
	fclose(Assembly);
	fclose(Optimized);
	
	return 0;
}

