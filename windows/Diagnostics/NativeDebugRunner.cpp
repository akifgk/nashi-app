// Diagnostic runner for Nashi's isolated Windows CI fixture. Prints call stacks,
// never process memory or local variables; preserves the debuggee's exit code.
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <cwchar>
#if !defined(NASHI_TRACE_LIBRARY)
#include <dbghelp.h>
#include <string>
#include <vector>
#pragma comment(lib, "dbghelp.lib")

static void writeStack(FILE* output,HANDLE process,HANDLE thread,CONTEXT context,DWORD code,DWORD firstChance) {
        std::fprintf(output,"\nNATIVE EXCEPTION code=0x%08lx firstChance=%lu thread=%lu\n",code,firstChance,GetThreadId(thread));
        SymSetOptions(SYMOPT_UNDNAME|SYMOPT_LOAD_LINES|SYMOPT_DEFERRED_LOADS|SYMOPT_FAIL_CRITICAL_ERRORS);
        bool initialized=SymInitialize(process,"srv*build\\native-symbols*https://msdl.microsoft.com/download/symbols",TRUE)!=FALSE;
        if(initialized)SymRefreshModuleList(process);
        STACKFRAME64 frame{};frame.AddrPC.Offset=context.Rip;frame.AddrStack.Offset=context.Rsp;frame.AddrFrame.Offset=context.Rbp;
        frame.AddrPC.Mode=frame.AddrStack.Mode=frame.AddrFrame.Mode=AddrModeFlat;
        for(int n=0;n<50&&frame.AddrPC.Offset;n++) {
            alignas(SYMBOL_INFO) char buffer[sizeof(SYMBOL_INFO)+MAX_SYM_NAME]{};
            auto symbol=reinterpret_cast<SYMBOL_INFO*>(buffer);symbol->SizeOfStruct=sizeof(SYMBOL_INFO);symbol->MaxNameLen=MAX_SYM_NAME;
            DWORD64 displacement=0;IMAGEHLP_MODULE64 module{};module.SizeOfStruct=sizeof(module);
            SymGetModuleInfo64(process,frame.AddrPC.Offset,&module);
            if(SymFromAddr(process,frame.AddrPC.Offset,&displacement,symbol))
                std::fprintf(output,"%02d %s!%s + 0x%llx\n",n,module.ModuleName,symbol->Name,static_cast<unsigned long long>(displacement));
            else std::fprintf(output,"%02d %s + 0x%llx [0x%llx]\n",n,module.ModuleName,static_cast<unsigned long long>(frame.AddrPC.Offset-module.BaseOfImage),static_cast<unsigned long long>(frame.AddrPC.Offset));
            if(!StackWalk64(IMAGE_FILE_MACHINE_AMD64,process,thread,&frame,&context,nullptr,SymFunctionTableAccess64,SymGetModuleBase64,nullptr))break;
        }
        if(initialized)SymCleanup(process);
        std::fflush(output);
}
#endif
#if defined(NASHI_TRACE_LIBRARY)
static wchar_t tracePath[32768]{};
static volatile LONG tracing=0;
static void rawStack(FILE* output,CONTEXT context) {
    std::fprintf(output,"NATIVE EXCEPTION code=0xC000000D thread=%lu\n",GetCurrentThreadId());
    for(int n=0;n<50&&context.Rip;n++) {
        HMODULE module=nullptr;wchar_t path[32768]{};
        if(GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(context.Rip),&module)&&GetModuleFileNameW(module,path,32768))
            std::fprintf(output,"FRAME\t%ls\t%llx\n",path,static_cast<unsigned long long>(context.Rip-reinterpret_cast<DWORD64>(module)));
        else std::fprintf(output,"JIT\t0x%llx\n",static_cast<unsigned long long>(context.Rip));
        std::fflush(output);
        DWORD64 base=0;auto function=RtlLookupFunctionEntry(context.Rip,&base,nullptr);
        if(function){PVOID data=nullptr;DWORD64 establisher=0;RtlVirtualUnwind(UNW_FLAG_NHANDLER,base,context.Rip,function,&context,&data,&establisher,nullptr);}
        else {context.Rip=*reinterpret_cast<DWORD64*>(context.Rsp);context.Rsp+=8;}
    }
}
static LONG CALLBACK traceException(EXCEPTION_POINTERS* exception) {
    if(exception->ExceptionRecord->ExceptionCode!=0xC000000D||InterlockedCompareExchange(&tracing,1,0)!=0)return EXCEPTION_CONTINUE_SEARCH;
    FILE* output=nullptr;
    if(_wfopen_s(&output,tracePath,L"a")==0&&output){
        // Do not import DbgHelp into the fixture: loading it early can change
        // native module shutdown order. Resolve these addresses afterward.
        __try{rawStack(output,*exception->ContextRecord);}__except(EXCEPTION_EXECUTE_HANDLER){std::fprintf(output,"Stack walk stopped at an unavailable frame.\n");}
        std::fclose(output);
    }
    return EXCEPTION_CONTINUE_SEARCH; // Observe only: preserve the original exception and process status.
}
extern "C" __declspec(dllexport) void __cdecl InstallTrace() {
    auto length=GetEnvironmentVariableW(L"NASHI_SMOKE_DIRECTORY",tracePath,32768);
    if(length==0||length>32700)return;
    wcscat_s(tracePath,L"\\native-exception-stack.txt");
    AddVectoredExceptionHandler(1,traceException);
    FILE* output=nullptr;if(_wfopen_s(&output,tracePath,L"a")==0&&output){std::fprintf(output,"Native exception observer armed; no debugger attached.\n");std::fclose(output);}
}
#else
static int resolve(const wchar_t* path) {
    FILE* input=nullptr;if(_wfopen_s(&input,path,L"r")!=0||!input)return 2;
    HANDLE process=GetCurrentProcess();SymSetOptions(SYMOPT_UNDNAME|SYMOPT_DEFERRED_LOADS|SYMOPT_FAIL_CRITICAL_ERRORS);
    if(!SymInitialize(process,"srv*build\\native-symbols*https://msdl.microsoft.com/download/symbols",TRUE)){std::fclose(input);return 3;}
    char line[32768];while(std::fgets(line,sizeof(line),input)) {
        if(std::strncmp(line,"FRAME\t",6)!=0){std::fputs(line,stdout);continue;}
        auto modulePath=line+6;auto separator=std::strchr(modulePath,'\t');if(!separator)continue;*separator=0;
        auto offset=std::strtoull(separator+1,nullptr,16);auto base=SymLoadModuleEx(process,nullptr,modulePath,nullptr,0,0,nullptr,0);
        if(!base){IMAGEHLP_MODULE64 existing{};existing.SizeOfStruct=sizeof(existing);auto loaded=GetModuleHandleA(modulePath);if(loaded&&SymGetModuleInfo64(process,reinterpret_cast<DWORD64>(loaded),&existing))base=existing.BaseOfImage;}
        alignas(SYMBOL_INFO) char buffer[sizeof(SYMBOL_INFO)+MAX_SYM_NAME]{};auto symbol=reinterpret_cast<SYMBOL_INFO*>(buffer);symbol->SizeOfStruct=sizeof(SYMBOL_INFO);symbol->MaxNameLen=MAX_SYM_NAME;DWORD64 displacement=0;
        if(base&&SymFromAddr(process,base+offset,&displacement,symbol))std::printf("%s!%s + 0x%llx\n",modulePath,symbol->Name,static_cast<unsigned long long>(displacement));
        else std::printf("%s + 0x%llx\n",modulePath,static_cast<unsigned long long>(offset));
    }
    SymCleanup(process);std::fclose(input);return 0;
}
static void stack(HANDLE process, DWORD threadId, DWORD code, DWORD firstChance) {
    HANDLE thread=OpenThread(THREAD_GET_CONTEXT|THREAD_QUERY_INFORMATION,FALSE,threadId);
    if(!thread)return;
    CONTEXT context{};context.ContextFlags=CONTEXT_FULL;
    if(GetThreadContext(thread,&context))writeStack(stderr,process,thread,context,code,firstChance);
    CloseHandle(thread);
}
int wmain(int argc,wchar_t** argv) {
    if(argc<2)return 2;
    if(argc==3&&std::wcscmp(argv[1],L"--resolve-stack")==0)return resolve(argv[2]);
    std::wstring command=L"\""+std::wstring(argv[1])+L"\"";
    for(int n=2;n<argc;n++)command+=L" \""+std::wstring(argv[n])+L"\"";
    std::vector<wchar_t> mutableCommand(command.begin(),command.end());mutableCommand.push_back(0);
    STARTUPINFOW startup{};startup.cb=sizeof(startup);PROCESS_INFORMATION process{};
    if(!CreateProcessW(argv[1],mutableCommand.data(),nullptr,nullptr,FALSE,DEBUG_ONLY_THIS_PROCESS,nullptr,nullptr,&startup,&process)) {
        std::fprintf(stderr,"CreateProcess failed: %lu\n",GetLastError());return 3;
    }
    CloseHandle(process.hThread);DWORD result=1;DEBUG_EVENT event{};
    while(WaitForDebugEvent(&event,INFINITE)) {
        DWORD status=DBG_CONTINUE;
        if(event.dwDebugEventCode==EXCEPTION_DEBUG_EVENT) {
            DWORD code=event.u.Exception.ExceptionRecord.ExceptionCode;
            if(code==0xC000000D||!event.u.Exception.dwFirstChance)
                stack(process.hProcess,event.dwThreadId,code,event.u.Exception.dwFirstChance);
            if(code!=EXCEPTION_BREAKPOINT&&code!=EXCEPTION_SINGLE_STEP)status=DBG_EXCEPTION_NOT_HANDLED;
        } else if(event.dwDebugEventCode==CREATE_THREAD_DEBUG_EVENT&&event.u.CreateThread.hThread)CloseHandle(event.u.CreateThread.hThread);
        else if(event.dwDebugEventCode==CREATE_PROCESS_DEBUG_EVENT&&event.u.CreateProcessInfo.hFile)CloseHandle(event.u.CreateProcessInfo.hFile);
        else if(event.dwDebugEventCode==LOAD_DLL_DEBUG_EVENT&&event.u.LoadDll.hFile)CloseHandle(event.u.LoadDll.hFile);
        else if(event.dwDebugEventCode==EXIT_PROCESS_DEBUG_EVENT) {
            result=event.u.ExitProcess.dwExitCode;ContinueDebugEvent(event.dwProcessId,event.dwThreadId,status);break;
        }
        if(!ContinueDebugEvent(event.dwProcessId,event.dwThreadId,status))break;
    }
    CloseHandle(process.hProcess);std::fprintf(stderr,"DEBUGGEE EXIT: 0x%08lx\n",result);return static_cast<int>(result);
}
#endif
