package com.generated.integrationtests;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Kontext-Wache: faehrt den Spring-Kontext einmal hoch. Schlaegt an, wenn eine Bean fehlt,
 * zwei Klassen dieselbe Aufgabe beanspruchen oder der Component-Scan nicht alle Module
 * erreicht — genau die Fehler, die Unit- und Slice-Tests NICHT sehen koennen, weil sie den
 * fehlenden Kollaborateur mocken. Nicht loeschen: sie ist das einzige Netz dafuer.
 */
@SpringBootTest
class ApplicationContextSmokeTest {

    @Test
    void kontext_faehrt_hoch() {
        // Kein Assert noetig: schon das Hochfahren ist die Zusicherung.
    }
}
