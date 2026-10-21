# Catalogo Windows CIE: ATR e maschere verificati

Il catalogo riproduce le 12 registrazioni di `DllRegisterServer` e la regola
`RegisterCard` del middleware ufficiale CIE 1.4.3.12, commit
`8dd385e9b867c98fa099df689e427cfd6cb06d44`. Non usa le sequenze parziali di
riconoscimento presenti in `ATR.cpp`.

Fonte: [StoreProvider.cpp ufficiale](https://github.com/italia/cie-middleware/blob/8dd385e9b867c98fa099df689e427cfd6cb06d44/CSP/CSP/StoreProvider.cpp).
L’installer NSIS ufficiale registra la DLL; è la sua funzione di registrazione
a contenere i valori. Una maschera assente nella chiamata ufficiale diventa
`FF` per ogni byte. Solo `CIE_3` (NXP) ha quattro byte finali variabili.

SHA-256 del file ufficiale: `d971757cdcad9443bf238aa3105e09bad91d38c64fb52b6a5521dcdbf50f5011`.

| Voce ufficiale | ATR completo (esadecimale) | Maschera (esadecimale) |
| --- | --- | --- |
| CIE_1 | `3B8F800180318065B0850300EF120FFF82900073` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_2 | `3B8F800180318065B085040011120FFF8290008A` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_3 | `3B8E80018031806549544E5850120F00000000` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000` |
| CIE_4 | `3B8B80018066475000B8007F8290002E` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_5 | `3B80800101` | `FFFFFFFFFF` |
| CIE_6 | `3B8B80018066475000B80094829000C5` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_7 | `3B8F80018031806549544A3442120FFF8290008B` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_8 | `3B8F80018031806549544A3441120FFF82900088` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_9 | `3B8F80018031806549544A3444120FFF8290008D` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_10 | `3B8F80018031806549544A3443120FFF8290008A` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_11 | `3B8F80018031806549544A3449120FFF82900080` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |
| CIE_12 | `3B8F80018031806549544A344C120FFF82900085` | `FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` |

## Uso nel pacchetto

Il catalogo è in `packaging/windows/card-catalog.json`; il relativo header
`card_catalog.h` è generato, non acquisito da Internet durante l’installazione.
La verifica offline confronta tutti i byte e le chiamate del file originale:

```powershell
python scripts/generate_windows_card_catalog.py --upstream-file <StoreProvider.cpp-verificato> --check
```

Il helper aggiorna i cinque valori documentati da Microsoft nel database
Calais nativo a 64 bit: `ATR`, `ATRMask`, `80000001`, `Crypto Provider` e
`Smart Card Key Storage Provider`. Non è richiesta una sessione del servizio
Smart Card. I nomi nuovi appartengono al progetto (`CIE ID Flutter Prototype
Web CIE_n`), non vengono utilizzati né sostituiti quelli ufficiali `CIE_n`.
[Riconoscimento Windows](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/smart-card-plug-and-play),
[valori di registrazione](https://learn.microsoft.com/en-us/windows-hardware/drivers/smartcard/minidriver-registration).

Le registrazioni preesistenti del progetto sono riconosciute anche dal percorso
del modulo e dai provider Microsoft. Il nome già usato viene mantenuto quando
il suo ATR rientra in una voce ufficiale; la maschera viene aggiornata a quella
del catalogo. Più vecchie registrazioni esatte comprese nella stessa maschera
NXP vengono accorpate per evitare corrispondenze duplicate. Le altre vecchie
registrazioni del progetto vengono conservate e aggiornate nel percorso del
modulo, senza ampliare il loro ATR. Non cambiano container, GUID, certificati,
PIN, archivio degli abbinamenti o preferenze dell’utente.

Le maschere di registrazioni estranee vengono confrontate per rilevare
sovrapposizioni; anche i conflitti sui nomi sono rilevati senza distinzione tra
maiuscole e minuscole. Un conflitto interrompe la configurazione prima delle
scritture. Un errore durante creazione, aggiornamento, accorpamento o rimozione
ripristina tutte le chiavi già toccate, compresi valori aggiuntivi preesistenti.
Se anche il ripristino fallisce, viene restituito il codice di ripristino richiesto.
La disinstallazione rimuove soltanto le registrazioni del progetto con proprietà
verificate; nessun archivio personale viene letto o modificato.

## Verifica

410 controlli C++ coprono catalogo, maschere, assenza di sovrapposizioni interne,
conflitti, ripetibilità, migrazione da ATR esatto, valori aggiuntivi, rollback di
tutti i passaggi e disinstallazione. Lo stesso adattatore Win32 usato dal helper
è provato in una chiave temporanea HKCU; non sono toccati HKLM, PC/SC, CIE,
servizi o dati personali. Passano inoltre 75 controlli setup e 124 del minidriver.
I test dell’installer e Flutter verificano conservazione dei dati e assenza di
richieste della carta nel pacchetto. La verifica in sola lettura
`CIE-Web-Setup.exe --plan-package` sul PC Windows ha restituito successo.

Il ponte nativo deve essere ricompilato insieme al helper, perché il controllo
di disponibilità incorpora anch'esso `setup_policy.h`. La sola ricompilazione
dell'installer non aggiorna questa logica. Il packager confronta gli hash degli
header consumati dal bridge con il catalogo corrente; la prova del binario
`scripts/check_windows_web_component.py` controlla lo stato senza operazioni
sulla carta. Questo intercetta il difetto riscontrato nel primo pacchetto.

La corrispondenza al catalogo ufficiale non equivale al collaudo fisico di tutte
le 12 varianti con il nostro minidriver. Il provider e il backend dei login già
collaudati restano invariati; il nuovo percorso installer/UAC resta da provare
personalmente sul PC.
