#ifndef S1705058_SYMBOLTABLE_H_INCLUDED
#define S1705058_SYMBOLTABLE_H_INCLUDED
#include "S1705058_SymbolInfo.h"
#include<iostream>
#include<fstream>
#include<vector>
#include<string>
#include<cstring>

// Class For Scope Table
class ScopeTable{

private:
    int BucketSize;
    int ChildTableCount; // Needed To Name Unique ID For Child
    SymbolInfo** Table; // The Hash Table
    ScopeTable* ParentScope;
    std::string UniqueID;

    // Used To Get Position Of A Symbol In The Table
    int HashFunction(std::string);

public:
    ScopeTable(int);
    ~ScopeTable();

    bool Insert(SymbolInfo*);
    SymbolInfo* LookUp(std::string);
    bool Delete(std::string);
    void Print(FILE*);
    void SetUniqueID();

    inline int GetChildTableCount(){return ChildTableCount;}
    inline void SetChildTableCount(int Child){ChildTableCount = Child;}
    inline ScopeTable* GetParentScope(){return ParentScope;}
    inline void SetParentScope(ScopeTable* Parent){ParentScope = Parent;}
    inline std::string GetUniqueID(){return UniqueID;}

};

ScopeTable::ScopeTable(int Size){
    BucketSize = Size;
    ChildTableCount = 0;

    Table = new SymbolInfo*[Size];
    for(int Counter=0; Counter<Size; Counter++){
        Table[Counter] = nullptr;
    }
    ParentScope = nullptr;
}

void ScopeTable::SetUniqueID(){
    if(ParentScope){
        UniqueID = ParentScope->UniqueID + "DOT" + std::to_string(ParentScope->ChildTableCount);
    }else{
        UniqueID = std::to_string(1);
    }
}

int ScopeTable::HashFunction(std::string Name){
    int TotalASCII = 0;
    for(auto Char: Name){
        TotalASCII += Char;
    }
    return TotalASCII%BucketSize;
}

ScopeTable::~ScopeTable(){
    // Clean the Hash Table, Including The Chains
    for(int Counter = 0; Counter < BucketSize; Counter++){
        SymbolInfo* Temp = Table[Counter];
        // Delete The Chains
        while(Temp){
            Table[Counter] = Temp;
            Temp = Temp->GetNextSymbol();
            delete Table[Counter];
        }
    }
    delete[] Table;
}

bool ScopeTable::Insert(SymbolInfo* Symbol){
    std::string Name = Symbol->GetSymbolName();
    int Position = HashFunction(Name);
    int Counter = 0;

    if(!Table[Position]){
        Table[Position] = Symbol;
    }else{
        SymbolInfo* Current = Table[Position];

        // It also checks if this name already exists in current scope
        while(Current){
            if(Current->GetSymbolName() == Name){
                delete Symbol;
                return false;
            }
            ++Counter;
            if(!Current->GetNextSymbol()){
                break;
            }
            Current = Current->GetNextSymbol();
        }
        Current->SetNextSymbol(Symbol);
    }
    return true;
}

SymbolInfo* ScopeTable::LookUp(std::string Name){
    int Position = HashFunction(Name);

    if(Table[Position]){
        SymbolInfo* Current = Table[Position];
        int Counter = 0;

        while(Current){
            if(Current->GetSymbolName() == Name){
                return Current;
            }
            Current = Current->GetNextSymbol();
            ++Counter;
        }
    }
    return nullptr;
}

bool ScopeTable::Delete(std::string Name){
    int Position = HashFunction(Name);

    if(Table[Position]){
        SymbolInfo* Current = Table[Position];
        SymbolInfo* Previous = nullptr;
        int Counter = 0;

        while(Current){

            if(Current->GetSymbolName() == Name){
                // If it has a previous symbol, the next of the previous will be the next of current
                if(Previous){
                    Previous->SetNextSymbol(Current->GetNextSymbol());
                }
                // If it has no previous symbol but a next symbol, then the next symbol will be the start of the chain
                else if(!Previous && Current->GetNextSymbol()){
                    Table[Position] = Current->GetNextSymbol();
                }
                // If there is no previous or next Symbol, it will become null
                else if(!Previous && !Current->GetNextSymbol()){
                    Table[Position] = nullptr;
                }

                delete Current;
                Current = nullptr;
                return true;

            }

            Previous = Current;
            Current = Current->GetNextSymbol();
            ++Counter;
        }
    }
    return false;
}

void ScopeTable::Print(FILE *File){
    fprintf(File, "ScopeTable # %s\n", UniqueID.c_str());
    for(int Counter = 0; Counter < BucketSize; Counter++){
        if(Table[Counter]){
            SymbolInfo* Current = Table[Counter];
			fprintf(File, "%d --> ", Counter);
            while(Current){
                fprintf(File, "< %s : %s> ",Current->GetSymbolName().c_str(), Current->GetSymbolType().c_str());
                Current = Current->GetNextSymbol();
            }
            fprintf(File, "\n");
        }
    }
    fprintf(File, "\n");
}

class SymbolTable{

private:
    ScopeTable* CurrentScope;
    int BucketSizeForTable;

public:
    SymbolTable(int);
    ~SymbolTable();
    void EnterScope(FILE*);
    void ExitScope(FILE*);
    bool Insert(SymbolInfo*);
    bool Remove(std::string);
    SymbolInfo* LookUp(std::string);
    SymbolInfo* LookUpCurrentScope(std::string);
    void PrintCurrentScope(FILE*);
    void PrintAllScopes(FILE*);
    bool InsertToGlobalScope(SymbolInfo*);
    std::string GetCurrentScopeID();
};

SymbolTable::SymbolTable(int Size){
    CurrentScope = nullptr;
    BucketSizeForTable = Size;
    EnterScope(nullptr); // Create Global Scope
}

SymbolTable::~SymbolTable(){
    // Delete All Available Scopes
    ScopeTable* Temp = CurrentScope;

    // Delete Scope then its parent scope and so on
    while(Temp){
        CurrentScope = Temp;
        Temp = Temp->GetParentScope();
        delete CurrentScope;
    }
    delete Temp;
}

void SymbolTable::EnterScope(FILE* Log){
    ScopeTable* NewScope = new ScopeTable(BucketSizeForTable);

    if(CurrentScope){
        CurrentScope->SetChildTableCount(CurrentScope->GetChildTableCount() + 1);
        NewScope->SetParentScope(CurrentScope);
    }
    NewScope->SetUniqueID();
    CurrentScope = NewScope;

    if(Log){
    	fprintf(Log, "New Scopetable with id %s created\n", CurrentScope->GetUniqueID().c_str());
    }
}

void SymbolTable::ExitScope(FILE* Log){
    ScopeTable* ToDelete = CurrentScope;
    if(ToDelete){
    	if(Log){
    		fprintf(Log, "Scopetable with id %s removed\n", ToDelete->GetUniqueID().c_str());
    	}
        CurrentScope = CurrentScope->GetParentScope();
        delete ToDelete;
    }
}

bool SymbolTable::Insert(SymbolInfo* Symbol){
    if(CurrentScope){
        return CurrentScope->Insert(Symbol);
    }
    return false;
}

bool SymbolTable::Remove(std::string Name){
    if(CurrentScope){
        return CurrentScope->Delete(Name);
    }
    return false;
}

SymbolInfo* SymbolTable::LookUp(std::string Name){
    ScopeTable* Current = CurrentScope;

    if(Current){
        while(Current){
            SymbolInfo* Symbol = Current->LookUp(Name);

            if(Symbol){
                return Symbol;
            }
            Current = Current->GetParentScope();
        }
    }
    return nullptr;
}

SymbolInfo* SymbolTable::LookUpCurrentScope(std::string Name){
    ScopeTable* Current = CurrentScope;

    if(Current){
        return Current->LookUp(Name);
    }
    return nullptr;
}

void SymbolTable::PrintCurrentScope(FILE* File){
    if(CurrentScope){
        CurrentScope->Print(File);
    }
}

void SymbolTable::PrintAllScopes(FILE* File){
    ScopeTable* Current = CurrentScope;

    if(Current){
        while(Current){
            Current->Print(File);
            Current = Current->GetParentScope();
        }
    }
}

bool SymbolTable::InsertToGlobalScope(SymbolInfo* ToAdd){
	if(CurrentScope){
		ScopeTable* Temp = CurrentScope;
		while(Temp->GetParentScope()){
			Temp = Temp->GetParentScope();
		}
		return Temp->Insert(ToAdd);
	}
	return false;
}

std::string SymbolTable::GetCurrentScopeID(){
	if(CurrentScope){
		return CurrentScope->GetUniqueID();
	}
	else{
		return "nan";
	}
}
#endif // S1705058_SYMBOLTABLE_H_INCLUDED
