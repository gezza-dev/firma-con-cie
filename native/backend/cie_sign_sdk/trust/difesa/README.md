# Autorità PKI Difesa

Certificati pubblici ottenuti dal [portale ufficiale PKI Difesa](https://pki.difesa.it/IT/default.aspx),
non dal PDF sottoposto a verifica. URL, impronte SHA-256 DER/PEM e date sono
in `manifest.json`; le impronte SHA-1 pubblicate dal Ministero sono usate solo
come confronto di provenienza, mai come algoritmo di firma o controllo del codice.

`difesa-signing.pem` e `difesa-tsa.pem` sono ancore esplicite del prototipo
condiviso, non installate nel sistema. Firme, vincoli, usi della chiave e revoca
restano verificati. Il ruolo TSA richiede il controllo RFC 3161 ed ESS/EKU.
Questa selezione non sostituisce le Trusted List europee né attesta qualificazione
eIDAS. I certificati sono materiale pubblico del Ministero, non soggetto alla
licenza BSD del nuovo codice. Gli aggiornamenti richiedono revisione di sorgenti
e provenienza; nessun certificato del documento viene promosso a radice.
