// SPDX-License-Identifier: BSD-3-Clause
// Isolated installer tests only. No PC/SC, registry, elevation or user stores.
#include <windows.h>
#include <fstream>
#include <filesystem>
#include <string>
int wmain(int argc,wchar_t** argv){
 if(argc<2)return 6;
 const std::wstring command(argv[1]);
 if(command!=L"--plan-package"&&command!=L"--install-package"&&command!=L"--unregister-package"&&command!=L"/install")return 6;
 wchar_t path[32768]{};
 if(GetEnvironmentVariableW(L"CIE_INSTALLER_TEST_LOG",path,32768)){
  std::ofstream log(std::filesystem::path(path),std::ios::app);
  for(const auto c:command)log<<static_cast<char>(c);
  log<<'\n';
 }
 wchar_t fail[256]{};
 if(GetEnvironmentVariableW(L"CIE_INSTALLER_TEST_FAIL",fail,256)&&command==fail)return 4;
 return 0;
}
