# Autorità CIE incluse nel prototipo

Certificati pubblici scaricati via HTTPS dalla pagina ministeriale:
https://www.cartaidentita.interno.gov.it/pa-e-imprese/certification-autority-2/

URL, data di acquisizione e SHA-256 degli archivi e dei PEM sono registrati in
`manifest.json`. Non sono chiavi private e non sono certificati dei cittadini.
Solo `root.pem` è un'ancora di fiducia esplicita dell'app. Le tre SubCA sono
candidati emittenti: firma, vincoli CA, usi della chiave, percorso e validità
temporale vengono comunque verificati. Una radice inclusa in un PDF, CMS o
risposta AIA non diventa mai attendibile per questo motivo.

Fingerprint SHA-256 DER della Root CA ministeriale:
`87364fb476e74962e7c495b9bbaf727813ee007cb56a0ada6ab9868123db267e`.

Il materiale è incorporato nel codice compilato; non viene installato nei
portachiavi macOS o negli archivi Windows. Le due CA della PKI Difesa sono incluse separatamente in `difesa/`, con
provenienza e hash espliciti. Per altre autorità si usa la policy nativa del
sistema, senza accettare automaticamente i certificati del documento.
La sostituzione della radice richiede una revisione esplicita dei sorgenti e
della provenienza; nessun aggiornamento di fiducia è scaricato automaticamente.

Questi certificati sono materiale crittografico pubblico del Ministero
dell'Interno, conservato senza modifiche ai certificati DER. La licenza BSD del
nuovo codice non viene attribuita ai certificati ministeriali. Non costituiscono
un elenco di prestatori qualificati eIDAS e non certificano il valore legale
delle firme controllate dall'app.
