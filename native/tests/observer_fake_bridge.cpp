// SPDX-License-Identifier: BSD-3-Clause
#include "cie_bridge.h"
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <chrono>
static char* copy(const char* s){auto p=static_cast<char*>(std::malloc(std::strlen(s)+1));std::strcpy(p,s);return p;}
extern "C" char* cie_bridge_load(const char*,const char*){return copy("{\"ok\":true}");}
extern "C" void cie_bridge_free(char* p){std::free(p);}
extern "C" char* cie_bridge_observe(){std::cout<<"SYNTHETIC_BLOCK_ENTERED"<<std::endl;for(;;)std::this_thread::sleep_for(std::chrono::hours(1));}
extern "C" char* cie_bridge_detect(){return copy("{\"ok\":true,\"readers\":[]}");}
