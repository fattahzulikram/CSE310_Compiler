#ifndef S1705058_SYMBOLINFO_H_INCLUDED
#define S1705058_SYMBOLINFO_H_INCLUDED

#include<fstream>
#include<vector>
#include<string>
#include<cstring>

class SymbolInfo{

private:
    std::string SymbolName;
    std::string SymbolType;

    std::string Identity; // Function or Variable
    std::string VariableType; // int or float etc
    std::string ReturnType; // For function

    // For Arrays
    int VariableSize = -1;
    int ArrayAccessVariable = -1;

    bool Function = false;
	
	// For Assembly
	std::string Code;
	std::string AssSymbol;
	std::string ImplementationID;
	
    SymbolInfo* NextSymbol;

public:
	std::vector<SymbolInfo*> ParamList;
	int IValue;
	float FValue;
	bool RetVal = false;
	bool GlobalVar = false;
	
	int* IntValue;
    float* FloatValue;
    char* CharValue;

    SymbolInfo(){
    	SymbolName = "";
		SymbolType = "";
		Identity = "";
		VariableType = "";
		ReturnType = "";

		IntValue = nullptr;
		FloatValue = nullptr;
		CharValue = nullptr;
    	NextSymbol = nullptr;
    }
    
    SymbolInfo(std::string Type){
    	SymbolName = "";
    	SymbolType = Type;
    	Identity = "";
		VariableType = "";
		ReturnType = "";

		IntValue = nullptr;
		FloatValue = nullptr;
		CharValue = nullptr;
   	 	NextSymbol = nullptr;
    }
    
    
    SymbolInfo(std::string Name, std::string Type){
    	SymbolName = Name;
    	SymbolType = Type;
    	Identity = "";
		VariableType = "";
		ReturnType = "";

		IntValue = nullptr;
		FloatValue = nullptr;
		CharValue = nullptr;
    	NextSymbol = nullptr;
    }
    ~SymbolInfo(){}
    
    inline std::string GetSymbolName(){return SymbolName;}
    inline std::string GetSymbolType(){return SymbolType;}
    inline std::string GetIdentity(){return Identity;}
    inline std::string GetVariableType(){return VariableType;}
    inline std::string GetReturnType(){return ReturnType;}
    inline int GetVariableSize(){return VariableSize;}
    inline int GetArrayAccessVariable(){return ArrayAccessVariable;}
    inline SymbolInfo* GetNextSymbol(){return NextSymbol;}
    inline std::vector<SymbolInfo*> GetParamList(){return ParamList;}
    inline std::string GetCode(){return Code;}
    inline std::string GetAssemblySymbol(){return AssSymbol;}
    inline std::string GetImplementationID(){return ImplementationID;}
    inline void SetSymbolName(std::string Name){SymbolName = Name;}
    inline void SetSymbolType(std::string Type){SymbolType = Type;}
    inline void SetIdentity(std::string ID){Identity = ID;}
    inline void SetVariableType(std::string Type){VariableType = Type;}
    inline void SetReturnType(std::string Type){ReturnType = Type;}
    inline void SetNextSymbol(SymbolInfo* Next){NextSymbol = Next;}
    inline void SetVariableSize(int Size){VariableSize = Size;}
    inline void SetArrayAccessVariable(int Access){ArrayAccessVariable = Access;}
    inline void SetCode(std::string code){Code = code;}
    inline void SetAssemblySymbol(std::string Ass){AssSymbol = Ass;}
    inline void SetImplementationID(std::string ID){ImplementationID = ID;}

    void CreateIntegerArray(){
    	IntValue = new int[VariableSize];
		for(int Counter = 0; Counter < VariableSize; Counter++){
			IntValue[Counter] = -1;
		}
    }
    
    void CreateFloatArray(){
    	FloatValue = new float[VariableSize];
		for(int Counter = 0; Counter < VariableSize; Counter++){
			FloatValue[Counter] = -1;
		}
    }
    void CreateCharacterArray(){
    	CharValue = new char[VariableSize];
		for(int Counter = 0; Counter < VariableSize; Counter++){
			CharValue[Counter] = '%';
		}
    }
};
#endif // S1705058_SYMBOLINFO_H_INCLUDED
