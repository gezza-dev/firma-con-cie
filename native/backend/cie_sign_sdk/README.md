# SDK di firma nativo per macOS

L'SDK, il middleware PKCS#11 e l'estensione CryptoTokenKit sono compilati dai
sorgenti per ARM64 e Intel. Il builder Universal unisce i due bundle e firma
i componenti incorporati. Gli archivi Intel storici sono esclusi dalla build.

## Compilazione

Servono macOS, Xcode/Command Line Tools, Python 3.10+, CMake 3.23+, make,
Perl, pkg-config, Meson 1.11+ e Ninja. Per l'app completa occorre Xcode completo.
Dalla radice del repository:

```sh
python3 scripts/build-native-sdk.py --arch arm64 --jobs 6
python3 scripts/build-native-sdk.py --arch x86_64 --jobs 6
```

I test Intel su Apple Silicon richiedono Rosetta. Il builder scarica gli
archivi fissati nei lockfile e ne verifica gli SHA-256. Non installa librerie
nelle cartelle di sistema. Le dipendenze sono in
`.build/dependencies/ARCH/prefix`, l'SDK in `.build/sign-sdk/ARCH/install`.
La cache viene invalidata quando cambiano ricette, sorgenti, compilatore,
architettura o SDK. Per ricostruire una sola dipendenza:

```sh
python3 scripts/build-dependencies.py --arch arm64 --only podofo --force
```

L'SDK statico richiede anche gli archivi e i framework elencati nel target
CMake `cie_sign_sdk`; il target propaga al consumatore C++17, le definizioni
e il collegamento necessario. Non incorporare soltanto `libcie_sign_sdk.a`
omettendo le sue dipendenze.

## Versioni e compatibilità 1.5.1

OpenSSL 3.5.9 LTS, Crypto++ 8.9.0, PoDoFo 1.1.2 LTS, zlib 1.3.2,
bzip2 1.0.8, libiconv 1.19, Expat 2.9.0, libpng 1.6.59, FreeType 2.14.3,
fontconfig 2.18.3, libxml2 2.15.4 e curl 8.23.0. Le versioni esatte, gli URL
e i checksum sono in `scripts/dependencies.lock.json`.

OpenSSL default e legacy sono statici e non caricano configurazioni esterne.
ENGINE rimane per la callback hardware, senza registrazione globale come
engine predefinito. Il provider legacy consente la lettura di PDF RC4;
HTTPS verifica certificati e nome del server con Apple SecTrust. Crypto++
è compilato in C++17 senza assembly. Gli header obsoleti 7.0/8.2 sono rimossi.

PoDoFo usa le API pubbliche 1.1: `PdfSigningContext` e firma CMS differita,
salvataggio incrementale, metadati e PNG trasparente. Le firme precedenti
mantengono i propri byte. L'aspetto non è garantito identico al vecchio fork
privato; il formato grafometrico proprietario senza sorgenti è rifiutato.
I normali flussi dell'app non richiedono dati grafometrici.

La verifica PDF controlla i ByteRange e il contenuto firmato, incluso il
formato legacy `adbe.pkcs7.sha1`. Il controllo OCSP/CRL verifica firme,
autorizzazione e tempi; informazioni insufficienti lasciano lo stato sconosciuto.
Vedere [Docs/SECURITY.md](../Docs/SECURITY.md) per ambito e test.

## Test e distribuzione

La suite genera chiavi temporanee ed esercita digest, RSA, callback ENGINE,
TLS 1.2/1.3, CMS, firma PDF, PNG trasparente, seconda firma incrementale,
alterazione dei documenti e lettura RC4/AES-128/AES-256. Gli stub hardware
sono presenti solo negli eseguibili di test. Il collaudo con carta e lettore
rimane necessario per i flussi hardware.

Il fork conserva BSD 3-Clause e le licenze specifiche dei componenti.
PoDoFo 1.1.2 è utilizzato sotto MPL 2.0; FreeType sotto FTL.
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md),
[LICENSE_AUDIT.md](../LICENSE_AUDIT.md) e
[Docs/REBUILDING.md](../Docs/REBUILDING.md) descrivono attribuzioni, sorgenti
corrispondenti e ricompilazione/ricollegamento con librerie LGPL modificate.
