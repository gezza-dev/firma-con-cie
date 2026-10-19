// SPDX-License-Identifier: BSD-3-Clause
#pragma once
#include "pairing_sod.h"
#include "cie-pkcs11/Crypto/sha256.h"
#include "cie-pkcs11/Crypto/sha512.h"
// The same strict six-DG/SOD check serves pairing and OS authentication.
namespace cie_pairing {
struct PairMaterial {
 ByteDynArray auth,services,sod,servicesKey,dh,certificate;uint8_t digest=0;
 template<class Card> void prepare(Card& card,int& phase){auto& ias=*card.ias;
  phase=-30;ias.ReadDappPubKey(auth);
  phase=-31;ias.ReadIdServizi(services);
  phase=-32;ias.ReadSOD(sod);
  phase=-33;digest=ias.GetSODDigestAlg(sod);
  phase=-34;ias.ReadServiziPubKey(servicesKey);
  phase=-35;ias.SelectAID_IAS();ias.ReadDH(dh);
  phase=-36;ias.SelectAID_CIE();
  phase=-38;auto groups=cie_pairing::sodDigests(sod);
  if(groups.size()!=6)throw std::runtime_error("SOD unsupported DG layout");
  for(uint8_t id:{0xa1,0xa2,0xa3,0xa4,0xa5,0x1b})if(!groups.count(id))throw std::runtime_error("SOD missing DG");
  phase=-37;card.secure();
 }
 template<class Card> void verifySod(Card& card,int& phase){auto& ias=*card.ias;ByteDynArray serial;auto& cert=certificate;
  phase=-41;ias.ReadSerialeCIE(serial);phase=-42;ias.ReadCertCIE(cert);
  phase=-43;std::map<uint8_t,ByteDynArray> hashes;
  ByteArray data[]={services.left(12),auth.left(GetASN1DataLenght(auth)),servicesKey.left(GetASN1DataLenght(servicesKey)),dh.left(GetASN1DataLenght(dh)),serial.left(9),cert.left(GetASN1DataLenght(cert))};
  const uint8_t tags[]={0xa1,0xa4,0xa5,0x1b,0xa2,0xa3};phase=-44;
  if(digest==1){CSHA256 hash;for(int i=0;i<6;++i)hashes[tags[i]]=hash.Digest(data[i]);cie_pairing::checkSodDigests(sod,hashes);ias.VerificaSOD(sod,hashes);}
  else if(digest==2){CSHA512 hash;for(int i=0;i<6;++i)hashes[tags[i]]=hash.Digest(data[i]);cie_pairing::checkSodDigests(sod,hashes);ias.VerificaSODPSS(sod,hashes);}
  else throw std::runtime_error("unsupported SOD");
 }
};
}
