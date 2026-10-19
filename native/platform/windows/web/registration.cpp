// SPDX-License-Identifier: BSD-3-Clause
// Explicit reversible registration of this prototype only. No PIN operations.
#include <windows.h>
#include <winscard.h>
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include <shlobj.h>
static constexpr const wchar_t* name=L"CIE ID Flutter Prototype Web";
static constexpr DWORD cardModule=0x80000001;
static constexpr DWORD keyStorageProvider=3; // SCARD_PROVIDER_KSP (newer Windows SDK)
static bool elevated(){HANDLE token=nullptr;if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token))return false;TOKEN_ELEVATION e{};DWORD bytes=0;bool ok=GetTokenInformation(token,TokenElevation,&e,sizeof(e),&bytes)&&e.TokenIsElevated;CloseHandle(token);return ok;}
static void jsonString(const std::wstring& text){std::cout<<'"';for(wchar_t c:text){if(c=='"'||c=='\\')std::cout<<'\\';if(c>=32&&c<127)std::cout<<char(c);else std::cout<<'?';}std::cout<<'"';}
int wmain(int argc,wchar_t** argv){
 if(argc==1||!wcscmp(argv[1],L"--help")){std::cout<<"--plan | --install ABSOLUTE_DLL | --remove\nNo PIN/PUK, no modification of other card types.\n";return 0;}
 bool install=!wcscmp(argv[1],L"--install"),remove=!wcscmp(argv[1],L"--remove");
 if((install&&argc!=3)||(!install&&argc!=2)||(!install&&!remove&&wcscmp(argv[1],L"--plan")))return 1;
 if((install||remove)&&!elevated()){std::cout<<"{\"status\":\"administrator_required\"}\n";return 2;}
 SCARDCONTEXT context=0;if(SCardEstablishContext(SCARD_SCOPE_SYSTEM,nullptr,nullptr,&context)){std::cout<<"{\"status\":\"pcsc_unavailable\"}\n";return 3;}
 struct Release{SCARDCONTEXT c;~Release(){SCardReleaseContext(c);}} release{context};
 if(remove){auto status=SCardForgetCardTypeW(context,name);if(status&&status!=SCARD_E_UNKNOWN_CARD)return 4;std::cout<<"{\"status\":\"prototype_registration_removed\"}\n";return 0;}
 DWORD size=0;if(SCardListReadersW(context,nullptr,nullptr,&size)||size<2){std::cout<<"{\"status\":\"no_reader\"}\n";return 5;}
 std::vector<wchar_t> readers(size);if(SCardListReadersW(context,nullptr,readers.data(),&size))return 6;
 if(readers[wcslen(readers.data())+1]){std::cout<<"{\"status\":\"connect_one_reader_only\"}\n";return 7;}
 SCARDHANDLE card=0;DWORD protocol=0;if(SCardConnectW(context,readers.data(),SCARD_SHARE_SHARED,SCARD_PROTOCOL_T1,&card,&protocol)){std::cout<<"{\"status\":\"no_card\"}\n";return 8;}
 struct Disconnect{SCARDHANDLE c;~Disconnect(){SCardDisconnect(c,SCARD_LEAVE_CARD);}} disconnect{card};
 BYTE atr[64];DWORD length=sizeof(atr),readerLength=4096,state=0;wchar_t reader[4096];if(SCardStatusW(card,reader,&readerLength,&state,&protocol,atr,&length))return 9;
 DWORD count=0;auto listed=SCardListCardsW(context,atr,nullptr,0,nullptr,&count);
 std::vector<std::wstring> matches;
 if(!listed&&count>1){std::vector<wchar_t> names(count);if(SCardListCardsW(context,atr,nullptr,0,names.data(),&count))return 10;for(auto p=names.data();*p;p+=wcslen(p)+1)matches.emplace_back(p);}
 else if(listed!=SCARD_E_UNKNOWN_CARD&&listed!=SCARD_S_SUCCESS)return 10;
 if(!install){std::cout<<"{\"status\":\"plan\",\"matchingCardTypes\":[";bool first=true;for(auto& match:matches){if(!first)std::cout<<',';first=false;jsonString(match);}std::cout<<"],\"prototypeName\":";jsonString(name);std::cout<<",\"adminRequiredForInstall\":true}\n";return 0;}
 // Never silently replace another CIE middleware or an existing installation.
 if(!matches.empty()){std::cout<<"{\"status\":\"existing_registration_requires_review\",\"noChanges\":true}\n";return 11;}
 std::filesystem::path file(argv[2]);PWSTR programFiles=nullptr;
 if(FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFiles,0,nullptr,&programFiles)))return 12;
 std::filesystem::path parentPath(programFiles);CoTaskMemFree(programFiles);
 if(!file.is_absolute()||!std::filesystem::is_regular_file(file)||file.filename()!=L"cie_prototype_minidriver.dll")return 12;
 auto parent=std::filesystem::weakly_canonical(parentPath),real=std::filesystem::canonical(file);
 auto relative=real.lexically_relative(parent);if(relative.empty()||relative.begin()->wstring()==L"..")return 12;
 // Registration is exact-ATR and restricted to the prepared private location.
 if(real.parent_path().parent_path().filename()!=L"CIE ID Flutter Prototype")return 12;
 std::vector<BYTE> mask(length,0xff);auto status=SCardIntroduceCardTypeW(context,name,nullptr,nullptr,0,atr,mask.data(),length);if(status)return 13;
 auto rollback=[&]{SCardForgetCardTypeW(context,name);};
 status=SCardSetCardTypeProviderNameW(context,name,SCARD_PROVIDER_CSP,L"Microsoft Base Smart Card Crypto Provider");
 if(!status)status=SCardSetCardTypeProviderNameW(context,name,keyStorageProvider,L"Microsoft Smart Card Key Storage Provider");
 if(!status)status=SCardSetCardTypeProviderNameW(context,name,cardModule,real.c_str());
 if(status){rollback();return 14;}
 std::cout<<"{\"status\":\"prototype_registered\",\"scope\":\"this_exact_atr\"}\n";return 0;
}
