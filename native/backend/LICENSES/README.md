# Testi di licenza e avvisi

I testi delle dipendenze native provengono dagli archivi delle versioni
fissate nei lockfile. Non sono riscritti come licenze del fork. Il manifest
`scripts/license-manifest.json` conserva percorso d'origine e SHA-256 di
ogni testo, oltre agli URL/checksum degli archivi.

`gnu/` contiene i testi GPL 2.0 e GNU Library GPL 2.0 per gli avvisi
espliciti dei sorgenti incorporati. La LGPL 2.1 di libiconv/libcharset è
contenuta nei rispettivi file. Le eccezioni valgono soltanto per i componenti
e le parti a cui i titolari le hanno concesse.

Gli avvisi in `embedded-sdk/` conservano condizioni e copyright presenti
nei sorgenti ancora incorporati. RSAEURO e SHA-1 legacy sono rimossi dallo
snapshot corrente e sostituiti con adattatori BSD/OpenSSL; i relativi vecchi
avvisi non sono attribuzioni del binario attuale.

Per Allura, il copyright e il Reserved Font Name provengono dal font 1.005
effettivamente incluso. Il testo standard OFL 1.1 è riprodotto dalla copia
pubblicata in Google Fonts, senza sostituire il copyright del font originale.

Leggere `THIRD_PARTY_NOTICES.md` e `LICENSE_AUDIT.md` per la matrice dei
componenti e le condizioni di distribuzione. Conservare questa cartella nella distribuzione
dei sorgenti e nei materiali delle release conformi alle licenze.
