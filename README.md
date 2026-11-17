# FaceCam

Sićušna macOS aplikacija, štedljiva za bateriju, koja prikazuje tvoju web kameru u plutajućem panelu iznad svih ostalih prozora. Bez efekata, bez pozadina, bez kompliciranih postavki. Samo kamera u obliku koji odabereš, na mjestu na zaslonu koje želiš.

## Mogućnosti

- **Uvijek na vrhu**: pluta iznad svih aplikacija, na svim Spaceovima i iznad aplikacija preko cijelog zaslona
- **Ne preuzima fokus**: klik na panel nikad ne oduzima fokus aplikaciji u kojoj radiš
- **Oblici**: kvadrat, pravokutnik (16:9), krug, zaobljeni pravokutnik
- **Promjena veličine**: kotačić miša, skrolanje s dva prsta ili pinch na panelu, ili gotove veličine (mala, srednja, velika, vrlo velika)
- **Micanje**: povuci panel bilo gdje na zaslonu
- **Načini kvalitete**:
  - **Normal**: preset `.medium` (~480p)
  - **Economy**: preset `.low` (~352×288), najmanja potrošnja resursa
- **Zrcalna slika**: uključena po zadanom, kao u video pozivima
- **Aplikacija u menu baru**: nema ikone u Docku, sve se kontrolira preko ikone u menu baru ili desnim klikom na panel
- **Pamti postavke**: oblik, veličina, pozicija, kvaliteta i zrcaljenje spremaju se između pokretanja

## Zašto je štedljiva

- Slika s kamere crta se izravno preko `AVCaptureVideoPreviewLayer`, pa se frameovi ne kopiraju niti obrađuju u kodu aplikacije
- Niska rezolucija snimanja (Normal ili Economy)
- Frame rate ograničen na 30 fps
- Kamera se potpuno zaustavlja kad je panel skriven ili kad se zaslon ili Mac uspava, pa su senzor kamere i njezina LED dioda ugašeni kad nisu potrebni
- Bez sjena, animacija i vizualnih efekata

## Zahtjevi

- macOS 12 ili noviji
- Xcode Command Line Tools (cijeli Xcode nije potreban):

  ```bash
  xcode-select --install
  ```

## Izgradnja i pokretanje

```bash
git clone <url-tvog-repozitorija>
cd <mapa-repozitorija>
bash build.sh
open FaceCam.app
```

`build.sh` kompajlira `main.swift` pomoću `swiftc`, slaže `FaceCam.app` s priloženim `Info.plist` i potpisuje je ad hoc. Pri prvom pokretanju macOS traži dozvolu za pristup kameri.

## Korištenje

| Radnja | Kako |
| --- | --- |
| Micanje | Povuci panel |
| Promjena veličine | Kotačić miša, skrolanje s dva prsta ili pinch na panelu |
| Gotova veličina | Izbornik → Mala / Srednja / Velika / Vrlo velika |
| Promjena oblika | Desni klik na panel ili ikona u menu baru |
| Kvaliteta | Izbornik → Kvaliteta: Normal / Economy |
| Zrcaljenje | Izbornik → Zrcalna slika |
| Sakrij / prikaži | Izbornik → Sakrij kameru / Prikaži kameru |
| Izlaz | Izbornik → Izlaz (⌘Q) |

## Rješavanje problema

**Nema slike s kamere / dozvola odbijena.** Uključi FaceCam u Postavke sustava → Privatnost i sigurnost → Kamera. Za ponovni prikaz upita za dozvolu:

```bash
tccutil reset Camera com.mateo.facecam
```

**Aplikacije nema u Docku.** To je namjerno. Potraži ikonu kamere u menu baru.

## Struktura projekta

```
main.swift    # cijela aplikacija (AppKit + AVFoundation)
Info.plist    # podaci o bundleu, opis korištenja kamere, način rada samo u menu baru
build.sh      # gradi i potpisuje FaceCam.app
```

## Tehnologije

Swift, AppKit i AVFoundation. Bez vanjskih ovisnosti.
