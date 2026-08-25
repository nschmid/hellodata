package com.generated.integrationtests;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Einstiegspunkt der Anwendung — vom Skelett erzeugt und bewusst im WURZEL-Package:
 * von hier deckt der Component-Scan alle Module ab. Keine zweite Klasse mit
 * @SpringBootApplication anlegen (zwei Konfigurationen brechen jeden @SpringBootTest).
 */
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
