# Avvisi del worker DSS e dei JAR

`manifest.json` confronta i 50 JAR effettivi con gli SHA-256 di `native/ltv/dependencies.lock.json` e identifica i testi originali qui conservati. I binari JAR non sono inclusi nel repository.

`DSS-LICENSE.txt` è la licenza originale del tag DSS 6.5.1, scaricata dal repository ufficiale esig/dss. I moduli `dss-*` e `specs-*` senza avvisi autonomi nel JAR fanno riferimento a questo testo. Gli altri testi sono estratti senza modifiche dai percorsi META-INF dei JAR fissati; i loro copyright e termini individuali restano applicabili.

Questa raccolta non contiene le JVM. Per distribuire le JVM OpenJDK/Temurin occorrono gli avvisi `legal` del runtime e il sorgente corrispondente previsto dalla licenza, oltre ai materiali di ricostruzione: vedere [docs/LICENSING.md](../../docs/LICENSING.md).
