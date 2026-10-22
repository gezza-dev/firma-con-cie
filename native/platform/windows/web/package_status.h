// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "setup_catalog.h"
namespace cie_setup {
// Read-only assessment: never applies the installation plan or opens a card.
// Version is the hash-pinned payload identity, not the pairing-storage ABI.
template<class OwnsModule, class ValidatePayload>
int packageStatus(const Database& database,const std::wstring& expectedModule,
                  OwnsModule ownsModule,ValidatePayload validatePayload){
 const auto plan=planCatalog(database,expectedModule,ownsModule);
 if(plan.code)return plan.code;
 Database owned;
 for(const auto& entry:database)if(ownedName(entry.first))owned.insert(entry);
 if(owned.empty())return 10;
 if(owned!=plan.after)return 11;
 return validatePayload()?0:9;
}
}
