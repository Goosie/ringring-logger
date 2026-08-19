# RingRing Logger

> Dit is een prototype / meetinstrument in ontwikkeling, geen productiesoftware.
> Interfaces, envelop-schema en corridorregistry veranderen zonder migratiepad.
> Wie hierop wil voortbouwen: lees eerst [docs/beslissingen.md](docs/beslissingen.md).
> Verschillende constanten in deze code zien eruit als vrij afstembare waarden
> maar zijn privacy-garanties; ze aanpassen zonder de reden te kennen breekt
> het ontwerp.
> Licentie: Apache License 2.0, zie [LICENSE](LICENSE) en [NOTICE](NOTICE).

Een **lokaal meetinstrument** (Flutter, alleen Android) dat tijdens verplaatsingen
sensor-, locatie- en batterijgegevens logt, met een **vooraf opgegeven
modaliteitslabel** (Lopen / Fiets / Auto / OV). Doel: grondwaarheid verzamelen
om later een modaliteitsclassifier tegen af te zetten.

Het is een meetinstrument, geen consumenten-app. Gebouwd voor een fietsrit op
**donderdag 13 augustus 2026**.

## Netwerk: alleen opt-in, alleen voor DELEN

Tijdens het **meten** stuurt de app geen enkele byte naar een server: geen
http-client, analytics, crash-reporting of sync. De ruwe rit (GPS-punten,
sensordata) verlaat het toestel nooit. Export naar JSON gaat uitsluitend via
een lokaal bestand dat de gebruiker zelf deelt (Android-deelmenu).

Er is één bewuste, opt-in uitzondering: het **DELEN**-scherm op het eindscherm.
Dat knipt de rit in corridor/uur/modaliteit-claims (nooit ruwe coördinaten) en
post die, alleen als de gebruiker daar zelf op drukt, via een websocket naar
Nostr-relays (zie `lib/delen/`, `lib/transport/`). Daarvoor staat de
`INTERNET`-permissie in het manifest — nergens anders in de app wordt hij
gebruikt.

## Wat de app doet

1. **Startscherm** — kies een modaliteit, vul optioneel een notitie en een
   toestel-label in (onthouden tussen sessies), doorloop de permissieflow en druk
   op START.
2. **Opnamescherm** — groot en contrastrijk: verstreken tijd, aantal fixes,
   laatste snelheid (km/u), laatste nauwkeurigheid (m), batterij (%) en het
   huidige modaliteitslabel. Knop **MODALITEIT WISSELEN** registreert een wissel
   binnen dezelfde opname (bijv. fiets aan de hand lopend). Knop **STOP**.
3. **Eindscherm** — samenvatting (duur, fixes, afstand via haversine-som,
   mediaansnelheid, batterijverbruik in procentpunten) en **EXPORTEER JSON**.

## Meetgedrag

- **Locatie**: `geolocator` met hoogste nauwkeurigheid, `distanceFilter: 0`,
  streaming zolang de opname loopt.
- **Batterij**: `battery_plus`, gesampled bij start, bij stop en elke 60 s.
- **Foreground service** (`flutter_foreground_task`): permanente notificatie
  "RingRing Logger meet" zolang een opname loopt, met wakelock zodat meten
  doorgaat met scherm uit / telefoon in de zak.
- **Crashbestendigheid**: de lopende opname wordt elke 30 s (plus bij elke wissel
  en batterijsample) weggeschreven naar `active_trip.json`. Bij het opstarten,
  als er zo'n niet-afgesloten opname staat en de service niet draait, biedt de
  app aan die te **herstellen** (bekijken en exporteren) of te **verwerpen**.

### Isolate-architectuur

Alle opname-logica (locatiestream, batterijsampling, wegschrijven, het
trip-bestand) draait in de **foreground-service-isolate** (`RecordingTaskHandler`).
Dit is bewust: als het scherm uitgaat en de app op de achtergrond komt, kan de
UI-isolate gepauzeerd worden, maar de service-isolate blijft loggen. De UI is een
pure weergave die live-statistieken ontvangt via `sendDataToMain` en commando's
(wisselen, stoppen) stuurt via `sendDataToTask`.

## Permissies (waarom)

| Permissie | Waarom |
|---|---|
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | GPS-fixes verzamelen |
| `ACCESS_BACKGROUND_LOCATION` | doorgaan met meten met scherm uit / app op achtergrond |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION` | langlopende locatie-service (Android 14+ eist het type) |
| `POST_NOTIFICATIONS` | meet-notificatie tonen (Android 13+) |
| `WAKE_LOCK` | CPU wakker houden zodat samplen doorloopt met scherm uit |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | systeemdialoog om batterijoptimalisatie uit te zetten |
| `INTERNET` | uitsluitend de opt-in DELEN-flow: claims posten naar Nostr-relays |

`RECEIVE_BOOT_COMPLETED` wordt door `flutter_foreground_task` toegevoegd; de app
gebruikt géén auto-start op boot (`autoRunOnBoot: false`).

### Runtime-permissieflow (Android 11+)

1. Voorgrond-locatie aanvragen.
2. Uitlegscherm, daarna **achtergrondlocatie** ("Altijd toestaan").
3. Notificatiepermissie (Android 13+).
4. Knop "batterijoptimalisatie uitschakelen" opent de systeemdialoog.

Elke geweigerde permissie geeft een duidelijke melding; de app crasht niet. START
is uitgeschakeld tot een modaliteit gekozen is én voorgrond + achtergrond +
notificaties rond zijn.

## Bouwen

```bash
flutter pub get
flutter analyze
flutter build apk --debug          # → build/app/outputs/flutter-apk/app-debug.apk
```

> `compileSdk` staat expliciet op **37** in `android/app/build.gradle.kts` omdat
> `permission_handler_android` dat vereist. `minSdk` is 26. `applicationId` is
> `nl.goosielabs.ringringlogger`.

## Installeren

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Doorloop op het toestel de permissieflow (kies bij achtergrondlocatie "Altijd
toestaan") en zet batterijoptimalisatie uit voor betrouwbaar meten met scherm uit.

## Exportformaat

Bestandsnaam: `trip-YYYYMMDD-HHMMSS-<modaliteit>-<toestellabel>.json` (tijd in UTC).

Veldnamen `lat`/`lng`/`speed`/`date` zijn bewust identiek aan de oude
Ring-Ring-export, zodat één parser beide datasets aankan. `speed` staat in **m/s**
zoals de sensor hem geeft (niet omgerekend in de opslag; km/u wordt alleen op het
scherm getoond). Alle tijden in UTC met `Z`-suffix. `osActivity` is leeg (zie
hieronder). Schema:

```json
{
  "id": "<uuid>",
  "appVersion": "0.1.0+1",
  "deviceLabel": "perry-pixel",
  "note": "stad en buitenweg",
  "start": "2026-08-13T09:14:02Z",
  "end": "2026-08-13T10:02:44Z",
  "declaredModality": "bike",
  "modalitySwitches": [ { "at": "2026-08-13T09:41:10Z", "modality": "walk" } ],
  "osActivity": [],
  "battery": [ { "at": "2026-08-13T09:14:02Z", "level": 87 } ],
  "points": [
    { "lat": 52.3865343, "lng": 4.9524378, "speed": 5.1, "accuracy": 3.2,
      "heading": 84.0, "altitude": 12.3, "date": "2026-08-13T09:14:05Z" }
  ]
}
```

## Wat ontbreekt / openstaande punten

- **Activiteitsherkenning (OS-labels lopen/fietsen/voertuig) is NIET ingebouwd.**
  De app werkt volledig zonder. Het `osActivity`-veld staat er wel (altijd lege
  lijst) zodat het schema stabiel blijft. Reden voor weglaten: om de build vóór de
  deadline gegarandeerd groen te houden is geen extra activity-recognition-pakket
  toegevoegd. De `ACTIVITY_RECOGNITION`-permissie is daarom óók weggelaten. Dit is
  een bewuste, gedocumenteerde keuze; toevoegen kan later zonder het schema te
  breken (vul dan `osActivity` en voeg de permissie + het pakket toe).

## Projectstructuur

```
lib/
  main.dart                       app-entry, thema, routing, herstelprompt
  models/trip.dart                Trip/TripPoint/... + JSON + samenvatting (haversine, mediaan)
  services/
    trip_storage.dart            lezen/schrijven active_trip.json, last_trip.json, export
    recording_task_handler.dart  achtergrond-isolate: opname-logica
    trip_service.dart            UI-kant: service starten/stoppen, commando's
    permissions.dart             twee-staps permissieflow
  screens/
    start_screen.dart
    recording_screen.dart
    end_screen.dart
  widgets/big_button.dart
```

`docs/beslissingen.md` — genummerde architectuurbeslissingen: wat er gekozen
is, waarom, wat breekt als je het terugdraait, en waar in de code.

## Toegevoegde dependencies

`geolocator`, `flutter_foreground_task`, `battery_plus`, `share_plus`,
`permission_handler`, `path_provider`, `uuid`, `shared_preferences`.

## Licentie

Apache License 2.0, copyright 2026 Perry Smit — zie [LICENSE](LICENSE). Bij
hergebruik of afgeleid werk moet het [NOTICE](NOTICE)-bestand mee.

Wegvakdata (NWB) komt van PDOK / Rijkswaterstaat onder CC0 1.0 en valt niet
onder de Apache-licentie van deze code.

Dit is experimentele software, zonder garantie ("AS IS"); gebruik in
productie is voor eigen rekening.
