# Widget Customize – teljes QA hibalista (57 widget)

2026-10-01 · build 0.7.1 (25) · `feature/widgets-v2`

**Mit teszteltem.** Mind az 57 widgetet, mindegyiket automatikus és Custom elrendezésben:
- **Minden beállítás szélsőséges értéken:** font, szöveg, szimbólum, kép, vonal, gomb, színek, háttér, elrendezés, formátumok és viselkedés.
- **A widget minden mérete.**
- **Szélsőséges kombinációk:** 96 pt + Expanded + Letters 10 + nagybetű, 3 sor, Padding 24 + Scale 150%.
- **Keret:** minden fogantyú ±1000 pt-ot húzva, minden irányba mozgatva, Locked állapotban is.
- **Parancsok:** Undo ×200, Redo ×200, Flip, a négy + Add dekoráció, ⌘D, Delete, szem ikon / Shown, Reset Widget, Copy/Paste.

Ez összesen kb. 4 400 kirajzolt állapot. Ezen felül widgetenként élő képernyőképet készítettem a valódi appban minden elemről, és a videóban látott hibákat valódi egérhúzással megismételtem.

- Widgetenkénti részletes eredmények: [WIDGET-CUSTOMIZE-QA-RESZLETEK.md](WIDGET-CUSTOMIZE-QA-RESZLETEK.md)
- Az automatikus teszt újrafuttatása: `NI_QA=1 Scripts/test.sh --filter WidgetQASweepTests`
  - Egy widget: `NI_QA_KIND=nowPlaying`
  - Az összeomló esetek kihagyása: `NI_QA_SAFE=1`
  - Kimenet: `$TMPDIR/WidgetQA/`

A teszt idejére elmentettem a widget-beállításaidat, a végén visszaállítottam őket; bájtra azonosak.

---

## Állapot a javítások után (2026-10-01, újrasöprés)

A teljes söprés újrafutott mind az 57 widgeten, a teljes tesztcsomag (884 teszt, 528 widget-pillanatkép, render-mátrix) zöld. A pillanatképeket nem kellett újra rögzíteni. Egy-egy időzítésre érzékeny teszt a teljes futás terhelése alatt elbukhat (minden futásnál más), de külön futtatva mindegyik átmegy.

| Mérés | Eredeti | Most |
|---|---|---|
| Összeomlás (K1, K2) | 2 | 0 |
| Custom gombra megváltozó kép (L1) | ~17 widget | 0 |
| Szem ikonnal rejtve is látszik (L6) | 50 widget | 0 |
| Kilóg a widgetből (keret vagy rajz) | 27 widget | 3 eset (lásd lent) |

**Javítva:** K1–K2, L1–L4, L5 (a Padding a widget méretéhez korlátozva), L6, L7, L8 (Timer, Stopwatch), L10, N1–N8, N10–N16, valamint az 5. fejezet összes tétele:
- a Paste Style tiltva, ha nincs mit beilleszteni;
- a Copy Style átviszi a Scale-t, az irányt, az igazítást és az S/M/L méreteket is;
- a Make Room visszavonható;
- a Divider inspektora a kitöltőszínt és az átlátszóságot mutatja, a Shape-é a kitöltőszínt, a keretet és az átlátszóságot.

**Nem hiba:** L9 (a gyűrű szándékosan veszi körül az ikont és az értéket) és a Shortcut ovális gombja (a képösszefűző eszköz torzítása volt).

**Ami a söprésben még megjelenik, de nem törés:**
- *Elem eltűnik* automatikus elrendezésben Padding 24 + Scale 150%, csupa 96 pt-os szöveg vagy minden elem L méretben mellett: az automatikus elrendezés hely híján a kisebb prioritású elemeket a „Didn't fit” tálcára teszi. Ez a tervezett működés. Layout = Button mellett a név és az állapot szándékosan nem látszik.
- *Átfedés* Scale 50% mellett a kontrolloknál: a név és az állapot sorkerete 1,7 pt-ot fed át, a betűk nem érnek össze (képen ellenőrizve). Cover elrendezésben a szöveg szándékosan a borítón van.
- *A szöveg kilóg a keretéből* 1–4 pt-tal szélsőséges Scale mellett; a widgeten belül marad.
- *3 kilógás:* a Now Playing borítója Nudge Y = 40 pt-tal (a felhasználó tolja ki); a Charger 1×1 szimbóluma 96 pt-on 2,4 pt-tal; a Battery 4×3 „minden L” mellett 56 képpontnyit.

**Nyitva (nem volt a jóváhagyott csoportokban):** N9 (Lines / Too Long automatikus elrendezésben), és a 4. fejezet: Case csak számokon, Alignment Custom módban, a 96 pt elérhetetlensége, Symbol Filled / Rendering változat nélküli ikonokon, Layout = Button mellett szerkeszthetőnek látszó Name / Status.

**A javítás közben talált és javított további hibák:**
- szintetikus dőlt betűnél a Stopwatch kijelzője óriási keretet kapott;
- Custom módban a gomb a felirat vagy a forma váltása után is a régi méretéhez igazodott, ezért kilógott;
- Custom módban egy újra bekapcsolt elem a widget közepére, a kijelzőre került; most szabad helyre kerül;
- a feliratos lejátszógombok „csak ikon” tartaléka nem működött, mert a gombsor nem kapott szélességet;
- a Now Playing léptetőgombjai Custom módban eltűntek, mert a rejtett elemek szűrője a gomb részeit is rejtettnek vette;
- a Timer, a Now Playing, a Countdown és a Disk Space rögzített nagy betűvel kitolta az elemeit a widgetből.

---

## 1. Összeomlás

| # | Hiba | Hol | Reprodukció |
|---|---|---|---|
| **K1** | **Clipboard: az app összeomlik.** Mivel a beállítás elmentődik, minden újraindításkor újra összeomlik. | [ToolKinds.swift:217](../../Sources/NotchIslandKit/Views/Widgets/Families/ToolKinds.swift) – `Int(size.height / rowHeight)`, ahol a magasság 0, így 0/0 = NaN | Clipboard 4×1-es méretben, Layout ▸ Padding = 24. Élőben igazolva. |
| **K2** | **Up Next: ugyanez.** | [TimeKinds.swift:348](../../Sources/NotchIslandKit/Views/Widgets/Families/TimeKinds.swift) | Up Next 4×1-es méretben, Padding = 24. Élőben igazolva. |

A Padding csúszka 24 pt-ig enged, de egy egysoros (44 pt magas) widgetben ennyi margó mellett 0 pt hely marad a tartalomnak. Lásd még M3.

## 2. Látható törés (elem eltűnik, kilóg, átfed, olvashatatlan)

| # | Hiba | Hány widget | Bizonyíték |
|---|---|---|---|
| **L1** | **A Custom gomb önmagában megváltoztatja a widgetet.** Semmi mást nem kell állítani, a feliratok és értékek mégis levágódnak. Példák: „Case 26%” → „Case 26…”, „Maximum Capacity” → „Maximum Capac…”, „88%” → „88…”, „Muted” → „Mut…”, „Cupertino” → „Cuperti…”, „October 1., Thursday” → „Oct 1., Thu”, „2026. October” → „2026. Octo…”. A Battery-ből két elem (Percentage, Time remaining) a tálcára kerül. A feloldás a szöveget pontosan a betűk szélességére szabja, ami a valódi kijelzőn egy hajszállal kevés. (A tesztcsomag ezt nem fogta meg, mert más notch-mérettel számol.) | kb. 17: AirPods, Battery és a 6 akkumulátor-widget, Charger, Countdown, Disk Space, Display és Keyboard Brightness, Volume, Uptime, World Clock, Network, Calendar, Date & Time | [img/01](img/01-custom-levagja-a-szoveget.jpg) |
| **L2** | **A szövegkeret olvashatatlan méretre zsugorítható.** A Title élőben 67,5×4 pt-ra ment (a videóban 22,5×2 pt-ra). Szövegnél a minimum 1×1 pt ([LayoutDrag.swift:112](../../Sources/NotchIslandKit/Views/Settings/Studio/Layout/LayoutDrag.swift)). Az automatikus teszt ezen felül 6×4 pt alá zsugorítható keretet talált a Battery Power, Battery Temperature, Display / Keyboard Brightness és Volume widgeteken. | minden szöveges elem | [img/02](img/02-cim-4pt-re-osszenyomva.png) |
| **L3** | **Az alsó fogantyút a tetején túlra húzva** az elem a widget legfelső szélére, a belső margóba ugrik. Bár csak függőlegesen húztam, a szélessége is változik (129 → 131,5). | Now Playing (élő); valószínűleg mind | [img/06](img/06-also-fogantyu-felcsuszik.png) |
| **L4** | **Semmi nem vágódik a keretére.** Nagy betűméretnél a szöveg rálóg a szomszédaira és kilóg a widgetből. Például Wi-Fi „On” 96 pt-on, vagy Now Playing csupa nagybetűvel, Expanded betűvel és nagy betűközzel. A szövegméret csak a keret magasságából számol, a szélességből nem. | 27 widget (az összes kontroll, Now Playing, Countdown, Disk Space, Charger) | [img/04](img/04-kilogas-es-atfedes.jpg) |
| **L5** | **Padding 24, illetve Padding 24 + Scale 150%** mellett az elemek eltűnnek: 419 eset, szinte minden egy- és kétsoros widgeten. A csúszka nincs a widget méretéhez korlátozva. | 50 | |
| **L6** | **A szem ikon és a Shown kapcsoló eltér.** Custom elrendezésben az outline-ban szemmel elrejtett elem továbbra is kirajzolódik, ráadásul tartalék méretben. A Shown kapcsoló jól működik. | mind az 50 Custom-képes widget | |
| **L7** | **Reset Widget átmenete.** Kb. 0,1 s-ig két inspektor rajzolódik egymásra: a Keep Shape / Shown / Locked sorok összecsúsznak, az S M L gombok a Width sorra kerülnek. A vásznon a kijelölő keret még a régi méretű, a szöveg viszont már az új. | mind | [img/03](img/03-reset-widget-atmenet.jpg) (a 1.15–1.25 s-os kockák) |
| **L8** | **Kilógás a saját keretből.** Timer és Stopwatch: Custom elrendezésben a nagy betűközzel vagy nagy betűvel írt számjegyek kilógnak a keretükből (darabonként vágódnak, nem egyben zsugorodnak). Shelf: Scale 150% mellett a felirat kilóg. Now Playing: Lines = 3 mellett a cím kilóg a keretéből. | Timer, Stopwatch, Shelf, Now Playing, Assistant | |
| **L9** | **Ring elrendezés.** Volume, Brightness és Keyboard Brightness: a gyűrű átfedi az ikont és az értéket. Ugyanez Custom elrendezésben nagy betűvel. | 3 | |
| **L10** | **Button label „withTitle”** a Now Playing előző/következő gombjain: a gombok kilógnak a widget alján. Stopwatch: Custom + roundedRectangle forma esetén a gomb kilóg. | 2 | |

## 3. Beállítás, amely nem csinál semmit

Kép-összehasonlítással igazolva (0 eltérő bájt), a kódban megnézve az okát. Amit a tesztkörnyezet adathiánya okozhatott (üres Shelf, álló Stopwatch, 0%-os akkumulátor), azt a mellékletben külön jelöltem, és nem vettem ide.

| # | Beállítás | Hol hatástalan | Ok |
|---|---|---|---|
| **N1** | **Italic (On)** | Minden SF Rounded betűs szám: az olvasó widgetek értékei, Timer, Stopwatch, Date & Time, Battery (14 widget) | Az SF Rounded-nek nincs dőlt változata, a jelölés csendben elvész ([WidgetTypography.swift:59](../../Sources/NotchIslandKit/Views/Widgets/Style/WidgetTypography.swift)). |
| **N2** | **Clock: 12-Hour** | Date & Time (élőben igazolva: 12-Hour mellett 17:56) | `clockLocale` beállítja a hourCycle-t, de a megjelenítés mégis 24 órás marad. |
| **N3** | **Wording (átnevezés)** | Mind a 26 kontroll neve és a Siri neve | `ControlFamily` a `control.title`-t, a Siri egy rögzített „Siri” szöveget rajzol; a `labelOverride`-ot nem olvassák. |
| **N4** | **Battery: minden szöveg- és szimbólumbeállítás** (font, szín, méret, opacitás, Weight, Rendering, Filled, Backing) | Battery „glyph” nézet | A százalék a `BatteryGlyph`-be van rajzolva, amely nem olvassa a stílust. |
| **N5** | **Line ▸ Fill Style = Gradient és Fill End szín** | Mind a 7 vonal: Now Playing progress, a 3 szint-csúszka, System CPU/RAM, Battery Chart | A `ResolvedLine.fillEnd` értékét semmi nem olvassa. |
| **N6** | **Line: Thickness, Ends, Track, Track Colour** | Volume, Brightness, Keyboard Brightness (csúszka nézet), Battery Chart | A csúszka csak a kitöltés színét kapja meg; a Battery Chart nem használja a vonalstílust. |
| **N7** | **Stack: Spacing, Direction, Alignment** | Mind a 13 olvasó widget (az akkumulátor-widgetek, World Clock, Countdown, Network, Disk Space, Uptime, AirPods) | Csak egy használaton kívüli planner olvassa; a `ReadingWidget` saját, fix stackeket használ. |
| **N8** | **Layout ▸ Scale 150%** Custom elrendezésben | mind az 50 | A `reflow` 1-re korlátozza, a csúszka mégis 150%-ig megy. |
| **N9** | **Text ▸ Lines 2 / 3 és Too Long** (Cut Start / Middle, Shrink) | Automatikus elrendezésben mind a 44 szöveges widget | A szöveg 1 sorra van tervezve. A Shrink to Fit csak 0,6-os skálát ad, ami az értékeken amúgy is ennyi. |
| **N10** | **Size S / M / L** | A kontrollok gombja (26), Analog Clock, Calendar, App Launcher, Shelf, Battery Chart | A gombot a rendelkezésre álló hely korlátozza, ezért a választásnak nincs hatása. |
| **N11** | **Symbol Backing és Backing Colour** | AirDrop, Bluetooth és a kör alakú gombú kontrollok, Battery | A gomb már eleve kör alakú; a Backing nem jelenik meg. |
| **N12** | **Second Colour** | 17 szimbólum | Csak Palette rendereléssel hat, de az inspektor ezt nem mondja. |
| **N13** | **Picture beállítások** (Corners, Border, Opacity, Nudge, Fill) | Shelf képei; a Fill a Now Playing borítóján (a kód szerint) | Ezek a nézetek nem hívják a `widgetImage`-et; a borító mindig kitölt. A Shelf a tesztben üres volt, élőben még igazolandó. |
| **N15** | **Percent decimals = 2** | 7 százalékos widget | Egész értékeknél nincs mit kiírni; értelmetlen opció. |
| **N16** | **Custom elrendezés a kontrollok „Button” nézetében** | 26 kontroll | Az editor felkínálja, de a widget továbbra is a magányos gombot rajzolja. |

## 4. Értelmetlen vagy félrevezető opció

- **Accent Colour** 35 widgeten semmit nem változtat Plate háttér mellett, mert nincs bennük gomb, sáv vagy gyűrű. Ezeknél vagy el kellene rejteni, vagy a leírásban jelezni.
- **Case** (kis/nagybetű) a csak számot tartalmazó értékeken (százalék, idő): nincs mit nagybetűsíteni.
- **Alignment** Custom elrendezésben: a feloldott keret pontosan a szöveg szélességű, ezért a Center és a Trailing semmit nem mozdít, amíg a keretet szélesebbre nem húzod.
- **Text pt 96** Custom elrendezésben: a mező 96-ig enged, de a keret korlátozza („Drawn at X pt — limited by room”). Hosszú szövegnél a 96 pt elérhetetlen.
- **Symbol Filled / Rendering** 22–37 ikonon: az ikonnak nincs kitöltött vagy többrétegű változata. Inkább kozmetikai, de a felhasználó azt látja, hogy „nem működik”.
- **Layout = Button** a kontrolloknál: a Name és a Status elem eltűnik, de az outline-ban továbbra is szerkeszthetőnek látszik.

## 5. Apróbb hibák a kódból (nem kattintottam végig)

- A **Paste Style** mindig aktív, akkor is, ha nincs mit beilleszteni (a `canPasteStyle`-t semmi nem használja).
- A **Copy Style** nem viszi át a Scale-t, az irányt, az elrendezést és az S / M / L méreteket.
- A **Make Room** nem kerül be a visszavonható lépések közé.
- **Dekorációk:** a Divider inspektorában a Thickness / Ends / Track nem hat; a Shape kitöltőszínét nem lehet beállítani.
- A Shown kapcsoló a `LayoutEdit.setShown`-t is hívja, a szem ikon nem (lásd L6).

## 6. Ami jól működik

Ezekre a teszt nem talált hibát:
- **Undo ×200 / Redo ×200:** pontosan visszaáll.
- **Flip kétszer:** visszaadja az eredetit.
- **A négy + Add dekoráció:** a widgeten belül jelenik meg.
- **⌘D és Delete.**
- **Locked elem:** nem mozdul.
- **Reset Widget:** törli a stílust.
- **Másik méretre kirajzolt Custom elrendezés:** nem lóg ki.
- **Seconds** (élőben is igazolva).

Analog Clock, App Launcher, Photo Frame, Up Next és Clipboard: a K1–K2 összeomláson kívül nincs érdemi hibájuk.

---

## Javasolt javítási csoportok (jóváhagyásra)

1. **Összeomlás (K1, K2).** Védelem a 0 és a negatív magasság ellen a soros widgetekben. A Padding legyen a widget méretéhez korlátozva (L5).
2. **Custom feloldás hűsége (L1).** A szövegkeretek kapjanak egy kis tartalékot, és a feloldás ne parkolja le a látható elemeket. A tesztcsomag a valódi notch-mérettel is fusson.
3. **Keret-határok (L2, L3).** A szövegkeret minimuma legalább egy olvasható sor legyen. Az alsó fogantyú ne fordítsa át és ne mozgassa el az elemet, a vízszintes méret ne változzon függőleges húzásra. Átméretezéskor az elem ne kerülhessen a belső margóba.
4. **Vágás és túlcsordulás (L4, L8, L9, L10).** A szöveg vágódjon a keretére, vagy a szélesség is számítson a betűméretbe; a gombok és a gyűrű férjenek el.
5. **Nem működő opciók (N1–N16).** Amit érdemes, azt bekötni: Italic (szintetikus dőlés), 12 órás óra, Wording, gradiens, csúszka-vonal, Stack-beállítások, Battery stílus. A többit elrejteni ott, ahol nem hat: Scale 150% Custom módban, Backing, S/M/L, Picture a Shelfen, Percent decimals.
6. **Szem ikon = Shown (L6), Reset átmenet (L7)**, majd az 5. fejezet apróságai.

Minden csoport után ugyanez a QA-csomag fut újra, és a lista frissül.
