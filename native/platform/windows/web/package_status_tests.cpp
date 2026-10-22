// SPDX-License-Identifier: BSD-3-Clause
#include "package_status.h"
#include <iostream>
#include <stdexcept>
using namespace cie_setup;
int main(){unsigned checks=0;auto check=[&](bool value){++checks;if(!value)throw std::runtime_error("package status check "+std::to_string(checks));};
 try{
 auto owns=[](const auto& path){return path==L"old"||path==L"expected";};
 auto installed=planCatalog({},L"expected",owns).after;
 unsigned validations=0;auto valid=[&]{++validations;return true;};
 auto assess=[&](const Database& db){auto before=db;auto result=packageStatus(db,L"expected",owns,valid);check(db==before);return result;};
 check(assess({})==10&&validations==0);
 check(assess(installed)==0&&validations==1);
 auto old=planCatalog({},L"old",owns).after;
 validations=0;check(assess(old)==11&&validations==0);
 auto mixed=installed;put(mixed.begin()->second,L"80000001",text(L"old"));
 check(assess(mixed)==11);
 auto partial=installed;partial.erase(partial.begin());check(assess(partial)==11);
 check(packageStatus(installed,L"expected",owns,[]{return false;})==9);
 auto foreign=installed;auto entry=foreign.begin()->second;
 foreign.emplace(L"Other middleware",entry);check(assess(foreign)==conflict);
 auto invalid=installed;put(invalid.begin()->second,L"80000001",text(L"foreign"));check(assess(invalid)==conflict);
 auto unrelated=installed;auto other=entry;put(other,L"ATR",binary({0x3b,0}));put(other,L"ATRMask",binary({0xff,0xff}));
 unrelated.emplace(L"Unrelated smart card",other);check(assess(unrelated)==0);
 auto annotated=installed;put(annotated.begin()->second,L"retained user annotation",text(L"keep"));check(assess(annotated)==0);
 // The registered package, not the existence of an unselected newer folder,
 // determines readiness. Multiple old folders never cause writes or repair.
 check(assess(old)==11);
 std::cout<<checks<<" read-only package status checks passed; no PCSC, registry writes, cache or PIN\n";
 return 0;
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';return 1;}
}
