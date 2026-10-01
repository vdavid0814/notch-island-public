# Widget Customize QA – widgetenkénti részletek

Ez a melléklet a [WIDGET-CUSTOMIZE-QA.md](WIDGET-CUSTOMIZE-QA.md) részletes adata: mind az 57 widget, minden kipróbált beállítás. Forrás: `NI_QA=1 Scripts/test.sh --filter WidgetQASweepTests` (automatikus) és élő képernyőképek a valódi appból.

Jelölések: **auto** = automatikus elrendezés, **custom** = Custom (szabad) elrendezés. A „nincs látható hatása” listából kihagytam az alapértéket választó opciókat (pl. Italic=Off, Lines=1, Alignment=Leading), mert azoktól nem várható változás. *(teszt: nincs adat)* = a tesztkörnyezetben az elem üres volt, ezért élőben kell igazolni.

## airDrop
- **Nincs látható hatása:**
  - `controlButton`: Colour.backing (auto/cust), Colour.primary (auto/cust), Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.backing=capsule (auto/cust), Symbol.backing=circle (auto/cust), Symbol.backing=roundedSquare (auto/cust), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust), Symbol.weight=black (auto/cust), Symbol.weight=ultraLight (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## airPodsBattery
- **Élő teszt:** Custom gombra a felirat „Case 26%” → „Case 26…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (11): Layout.padding=24 + scale 1.5 ×6, ALL largest+widest ×5
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## analogClock
- **Nincs látható hatása:**
  - `face`: Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto)

## appLauncher
- **Nincs látható hatása:**
  - `appIcons`: Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto), Layout.padding=0 (auto)

## appsLauncher
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×9, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## assistant
- **Nincs látható hatása:**
  - `assistantLabel`: Text.alignment=center (auto), Text.alignment=trailing (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto), Text.tooLong=middle (auto), Text.tooLong=shrink (auto), Text.wording (auto)
  - `widget`: Accent=red (auto), Layout.padding=0 (auto)
- **elem eltűnik** (4): Layout.padding=24 + scale 1.5 ×4
- **szöveg kilóg a saját keretéből** (1): Layout.scale=1.5 ×1

## battery
- **Élő teszt:** Custom gombra a Percentage és a Time remaining a tálcára kerül („Not on the widget”). A glyph nézetben a százalék az ikonba rajzolt, egyetlen szöveg- és szimbólumbeállítás sem hat rá.
- **Nincs látható hatása:**
  - `batteryGlyph`: Colour.backing (auto/cust), Colour.primary (auto/cust), Colour.secondary (auto/cust), Symbol.backing=capsule (auto/cust), Symbol.backing=circle (auto/cust), Symbol.backing=roundedSquare (auto/cust), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.points=6 (auto/cust), Symbol.points=96 (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust), Symbol.weight=black (auto/cust), Symbol.weight=ultraLight (auto/cust)
  - `percentage`: Font.design=monospaced (auto/cust), Font.design=rounded (auto/cust), Font.design=serif (auto/cust), Font.italic=on (auto/cust), Font.weight=black (auto/cust), Font.weight=ultraLight (auto/cust), Font.width=compressed (auto/cust), Font.width=expanded (auto/cust), Size=L (auto), Size=S (auto), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.colour (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto/cust), Text.lines=2 (auto/cust), Text.lines=3 (auto/cust), Text.opacity=0.1 (auto/cust), Text.points=6 (auto/cust), Text.points=96 (auto/cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `timeRemaining` *(teszt: nincs adat)*: Eye=off (auto/cust), Font.design=monospaced (auto/cust), Font.design=rounded (auto/cust), Font.design=serif (auto/cust), Font.italic=on (auto/cust), Font.weight=black (auto/cust), Font.weight=ultraLight (auto/cust), Font.width=compressed (auto/cust), Font.width=expanded (auto/cust), Shown=off (auto/cust), Size=L (auto), Size=S (auto), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.colour (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto/cust), Text.lines=2 (auto/cust), Text.lines=3 (auto/cust), Text.opacity=0.1 (auto/cust), Text.points=6 (auto/cust), Text.points=96 (auto/cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.duration=abbreviated (auto/cust), Format.duration=narrow (auto/cust), Format.duration=positional (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.padding=0 (auto), Layout.scale=1.5 (cust), Layout=glyph (auto), SwapSides (auto)
- **szem ikonnal rejtve is látszik (custom)** (1): Eye=off (custom) ×1
- **rajz kilóg a widgetből** (1): ALL sizes L ×1

## batteryChart
- **Nincs látható hatása:**
  - `chart` *(teszt: nincs adat)*: Colour.fill (auto/cust), Colour.track (auto/cust), Eye=off (auto/cust), Line.ends=butt (auto/cust), Line.ends=square (auto/cust), Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.fillStyle=valueScale (auto/cust), Line.thickness=1 (auto/cust), Line.thickness=16 (auto/cust), Line.track=0 (auto/cust), Line.track=1 (auto/cust), Shown=off (auto/cust), Size=L (auto), Size=S (auto)
  - `label`: Eye=off (cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `value`: Eye=off (cust), Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×16
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
- **elemek átfedik egymást** (2): Layout.scale=0.5 ×2
- **szöveg kilóg a saját keretéből** (1): Layout.scale=1.5 ×1

## batteryCycles
- **Élő teszt:** Custom gombra „of 1 000 Cycles” → „of 1 000 Cycl…”.
- **Nincs látható hatása:**
  - `label`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×5, ALL largest+widest ×4, Layout.padding=24 ×1, Layout.scale=1.5 ×1, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## batteryHealth
- **Élő teszt:** Custom gombra „Maximum Capacity” → „Maximum Capac…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.points=96 (cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (8): Layout.padding=24 + scale 1.5 ×3, ALL largest+widest ×2, Layout.padding=24 ×1, Layout.scale=1.5 ×1, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## batteryPower
- **Élő teszt:** Custom gombra „From the Charger” → „From the Char…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.points=96 (cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (9): Layout.padding=24 + scale 1.5 ×4, ALL largest+widest ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
- **keret 6×4 pt alá zsugorítható** (6): resize topLeading in 1000pt ×1, resize top in 1000pt ×1, resize topTrailing in 1000pt ×1, resize bottomLeading in 1000pt ×1, resize bottom in 1000pt ×1, resize bottomTrailing in 1000pt ×1

## batteryTemperature
- **Élő teszt:** Custom gombra „Battery” → „Batte…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.temperature=fahrenheit (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×5, ALL largest+widest ×4, Layout.padding=24 ×1, Layout.scale=1.5 ×1, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
- **keret 6×4 pt alá zsugorítható** (6): resize topLeading in 1000pt ×1, resize top in 1000pt ×1, resize topTrailing in 1000pt ×1, resize bottomLeading in 1000pt ×1, resize bottom in 1000pt ×1, resize bottomTrailing in 1000pt ×1

## batteryTime
- **Élő teszt:** Custom gombra „Battery” → „Batte…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.points=96 (cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.duration=abbreviated (cust), Format.duration=narrow (auto/cust), Format.duration=positional (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (11): Layout.padding=24 + scale 1.5 ×4, ALL largest+widest ×3, ALL sizes L ×2, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## bluetooth
- **Nincs látható hatása:**
  - `controlButton`: Colour.primary (auto/cust), Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.backing=capsule (auto/cust), Symbol.backing=circle (auto/cust), Symbol.backing=roundedSquare (auto/cust), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust), Symbol.weight=black (auto/cust), Symbol.weight=ultraLight (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×13, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (4): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## brightness
- **Élő teszt:** Custom gombra „88%” → „88…” (az érték maga csonkul).
- **Nincs látható hatása:**
  - `levelIcon`: Colour.secondary (auto/cust), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `levelSlider`: Colour.track (auto/cust), Line.ends=butt (auto/cust), Line.ends=square (auto/cust), Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.thickness=1 (auto/cust), Line.thickness=16 (auto/cust), Line.track=0 (auto/cust), Line.track=1 (auto/cust)
  - `levelValue`: Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Layout=slider (auto)
- **elem eltűnik** (10): Layout.padding=24 + scale 1.5 ×10
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout=ring ×2, ALL largest+widest ×2, Layout.padding=24 + scale 1.5 ×1
- **keret 6×4 pt alá zsugorítható** (6): resize topLeading in 1000pt ×1, resize topTrailing in 1000pt ×1, resize leading in 1000pt ×1, resize trailing in 1000pt ×1, resize bottomLeading in 1000pt ×1, resize bottomTrailing in 1000pt ×1

## calculator
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×13, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (4): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## characterViewer
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (17): Layout.padding=24 + scale 1.5 ×14, Layout=button ×3
- **elem kerete kilóg a widgetből** (14): ALL largest+widest ×10, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (5): ALL largest+widest ×5

## charger
- **Élő teszt:** Custom gombra „Not Charging” → „Not Chargi…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (8): Layout.padding=24 + scale 1.5 ×3, ALL largest+widest ×2, Layout.padding=24 ×1, Layout.scale=1.5 ×1, ALL sizes L ×1
- **elem kerete kilóg a widgetből** (1): ALL largest+widest ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## clipboard
- **Élő teszt:** Élőben: 4×1 méretben Padding = 24 → az app ÖSSZEOMLIK (ToolKinds.swift:217), és mivel elmentődik, minden indításkor újra.
- **Nincs látható hatása:**
  - `clipList`: Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto)

## clock
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.alignment=center (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×9, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## countdown
- **Élő teszt:** Custom gombra „Set a date” → „Set a da…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.duration=abbreviated (auto/cust), Format.duration=narrow (auto/cust), Format.duration=positional (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×7, ALL largest+widest ×5
- **elem kerete kilóg a widgetből** (6): ALL largest+widest ×6
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
- **rajz kilóg a widgetből** (2): ALL largest+widest ×2

## darkMode
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×11, Layout=button ×3, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (14): ALL largest+widest ×10, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (5): ALL largest+widest ×5

## dateTime
- **Élő teszt:** Custom gombra „October 1., Thursday” → „Oct 1., Thu”. Élőben: Clock = 12-Hour beállítva, mégis 17:56 látszik.
- **Nincs látható hatása:**
  - `dateLine`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `readout`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.clock=12h (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (8): Layout.padding=24 + scale 1.5 ×6, ALL largest+widest ×1, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2

## diskSpace
- **Élő teszt:** Custom gombra „Free of 494,33 GB” → „Free of 494,33…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value` *(teszt: nincs adat)*: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.letters=-2 (auto/cust), Text.letters=10 (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (14): Layout.padding=24 + scale 1.5 ×7, ALL largest+widest ×6, ALL sizes L ×1
- **elem kerete kilóg a widgetből** (6): ALL largest+widest ×6
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
- **rajz kilóg a widgetből** (2): ALL largest+widest ×2

## displaySleep
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (12): ALL largest+widest ×8, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (5): ALL largest+widest ×4, Text.points=96 ×1

## focus
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## home
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## keepAwake
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (12): ALL largest+widest ×8, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (4): ALL largest+widest ×4

## keyboardBrightness
- **Élő teszt:** Custom gombra „50%” → „50…”.
- **Nincs látható hatása:**
  - `levelIcon`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `levelSlider`: Colour.track (auto/cust), Line.ends=butt (auto/cust), Line.ends=square (auto/cust), Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.thickness=1 (auto/cust), Line.thickness=16 (auto/cust), Line.track=0 (auto/cust), Line.track=1 (auto/cust)
  - `levelValue`: Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Layout=slider (auto)
- **elem eltűnik** (10): Layout.padding=24 + scale 1.5 ×10
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout=ring ×2, ALL largest+widest ×2, Layout.padding=24 + scale 1.5 ×1
- **keret 6×4 pt alá zsugorítható** (6): resize topLeading in 1000pt ×1, resize topTrailing in 1000pt ×1, resize leading in 1000pt ×1, resize trailing in 1000pt ×1, resize bottomLeading in 1000pt ×1, resize bottomTrailing in 1000pt ×1

## lockScreen
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (12): ALL largest+widest ×8, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (4): ALL largest+widest ×4

## lowPowerMode
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Eye=off (cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (17): Layout.padding=24 + scale 1.5 ×14, Layout=button ×3
- **elem kerete kilóg a widgetből** (14): ALL largest+widest ×10, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (5): ALL largest+widest ×5

## microphone
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×13, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (4): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## missionControl
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Size=L (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (10): ALL largest+widest ×6, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (2): Layout.scale=0.5 ×1, Layout.padding=24 + scale 1.5 ×1
- **rajz kilóg a widgetből** (3): ALL largest+widest ×3

## monthCalendar
- **Élő teszt:** Custom gombra „2026. October” → „2026. Octo…”.
- **Nincs látható hatása:**
  - `label`: Eye=off (cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `monthGrid`: Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (7): Layout.padding=24 + scale 1.5 ×7
- **szem ikonnal rejtve is látszik (custom)** (1): Eye=off (custom) ×1
- **elemek átfedik egymást** (1): Layout.scale=0.5 ×1

## network
- **Élő teszt:** Custom gombra „↑ 0 KB/s” → „↑ 0 K…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×7, ALL largest+widest ×5, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## nightShift
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (14): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (14): ALL largest+widest ×10, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×5, Text.points=96 ×1

## notes
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## nowPlaying
- **Élő teszt:** Élőben: a cím jobb alsó sarkát befelé húzva 67,5×4 pt-ra zsugorodik, olvashatatlan. Az alsó fogantyút a tetején túlra húzva a cím a widget legfelső szélére ugrik, és a szélessége is változik. Reset Widget után ~0,1 s-ig két inspektor fedi egymást.
- **Nincs látható hatása:**
  - `artwork`: Picture.corners=0 (auto)
  - `progress`: Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust)
  - `widget`: Artwork.dim=1 (auto/cust)
- **elem eltűnik** (36): Layout.padding=24 + scale 1.5 ×34, Layout=cover ×1, Layout=minimal ×1
- **elem kerete kilóg a widgetből** (33): ALL largest+widest ×29, Button.label=withTitle ×4
- **szem ikonnal rejtve is látszik (custom)** (5): Eye=off (custom) ×5
- **elemek átfedik egymást** (7): Layout=cover ×5, Layout.scale=0.5 ×2
- **rajz kilóg a widgetből** (15): ALL largest+widest ×13, Picture.nudgeY=40 ×1, Button.label=withTitle ×1
- **szöveg kilóg a saját keretéből** (2): Text.lines=3 ×1, ALL 3 lines ×1

## outputMute
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×9, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## photoFrame
- **Nincs látható hatása:**
  - `photo`: Colour.border (auto), Picture.border=6 (auto), Picture.corners=0 (auto), Picture.corners=40 (auto), Picture.corners=circle (auto), Picture.fill=fill (auto), Picture.fill=fit (auto), Picture.nudgeX=40 (auto), Picture.nudgeY=40 (auto), Picture.opacity=0.1 (auto), Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto), Layout.padding=0 (auto)

## screenMirroring
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (19): Layout.padding=24 + scale 1.5 ×12, Layout=button ×3, Size=L ×1, Layout.padding=24 ×1, Layout.scale=1.5 ×1, ALL sizes L ×1
- **elem kerete kilóg a widgetből** (10): ALL largest+widest ×6, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (2): Layout.scale=0.5 ×1, Layout.padding=24 + scale 1.5 ×1
- **rajz kilóg a widgetből** (3): ALL largest+widest ×3

## screenshot
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×13, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (4): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (6): ALL largest+widest ×6

## shelf
- **Nincs látható hatása:**
  - `previews` *(teszt: nincs adat)*: Colour.border (auto/cust), Eye=off (auto/cust), Picture.border=6 (auto/cust), Picture.corners=0 (auto/cust), Picture.corners=40 (auto/cust), Picture.corners=circle (auto/cust), Picture.fill=fill (auto/cust), Picture.fill=fit (auto/cust), Picture.nudgeX=40 (auto), Picture.nudgeY=40 (auto), Picture.opacity=0.1 (auto/cust), Shown=off (auto/cust), Size=L (auto), Size=S (auto)
  - `shelfActions` *(teszt: nincs adat)*: Button.label=iconOnly (auto/cust), Button.label=withTitle (auto/cust), Button.look=bordered (auto/cust), Button.look=glass (auto/cust), Button.look=plain (auto/cust), Button.look=prominent (auto/cust), Button.shape=capsule (auto/cust), Button.shape=circle (auto/cust), Button.shape=roundedRectangle (auto/cust), Button.size=large (auto), Button.size=mini (auto), Button.size=regular (auto), Button.size=small (auto), Button.tintStrength=0.1 (auto/cust), Colour.tint (auto/cust), Eye=off (auto/cust), Shown=off (auto/cust)
  - `shelfCount`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **szem ikonnal rejtve is látszik (custom)** (1): Eye=off (custom) ×1
- **szöveg kilóg a saját keretéből** (14): Layout.padding=24 + scale 1.5 ×12, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1

## shortcut
- **Nincs látható hatása:**
  - `label`: Eye=off (cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (3): Layout.padding=24 + scale 1.5 ×3
- **szem ikonnal rejtve is látszik (custom)** (1): Eye=off (custom) ×1

## showDesktop
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (16): Layout.padding=24 + scale 1.5 ×11, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (12): ALL largest+widest ×8, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (4): ALL largest+widest ×4

## soundOutput
- **Nincs látható hatása:**
  - `controlButton`: Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Eye=off (cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (10): ALL largest+widest ×8, Text.points=96 ×2
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (4): ALL largest+widest ×4

## stageManager
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Size=L (auto), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (10): ALL largest+widest ×6, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (2): Layout.scale=0.5 ×1, Layout.padding=24 + scale 1.5 ×1
- **rajz kilóg a widgetből** (3): ALL largest+widest ×3

## stopwatch
- **Nincs látható hatása:**
  - `readout`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Font.width=compressed (auto/cust), Font.width=expanded (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `resetButton` *(teszt: nincs adat)*: Button.label=iconOnly (auto/cust), Button.label=withTitle (auto/cust), Button.look=bordered (auto/cust), Button.look=glass (auto/cust), Button.look=plain (auto/cust), Button.look=prominent (auto/cust), Button.shape=capsule (auto/cust), Button.shape=circle (auto/cust), Button.shape=roundedRectangle (auto/cust), Button.size=large (auto), Button.size=mini (auto), Button.size=regular (auto), Button.size=small (auto), Button.tintStrength=0.1 (auto/cust), Colour.tint (auto/cust), Eye=off (auto/cust), Shown=off (auto/cust)
  - `stopwatchButton`: Button.label=iconOnly (auto/cust), Button.look=prominent (auto/cust), Button.shape=circle (auto/cust), Button.size=small (auto)
  - `widget`: Layout.scale=1.5 (cust)
- **szem ikonnal rejtve is látszik (custom)** (1): Eye=off (custom) ×1
- **rajz kilóg a widgetből** (2): Button.shape=roundedRectangle ×1, Button.label=withTitle ×1
- **szöveg kilóg a saját keretéből** (10): ALL largest+widest ×9, Text.letters=10 ×1

## systemStats
- **Nincs látható hatása:**
  - `cpuLoad`: Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.fillStyle=valueScale (auto/cust), Line.track=1 (auto/cust)
  - `memoryLoad`: Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.fillStyle=valueScale (auto/cust), Line.track=1 (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust)
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×3

## timer
- **Nincs látható hatása:**
  - `addMinute` *(teszt: nincs adat)*: Eye=on (auto/cust), Shown=on (auto/cust)
  - `readout`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Font.width=compressed (auto/cust), Font.width=expanded (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `timerActions`: Button.label=iconOnly (auto/cust), Button.label=withTitle (auto/cust), Button.look=prominent (auto/cust), Button.shape=capsule (auto/cust), Button.size=small (auto)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (4): Layout.padding=24 + scale 1.5 ×4
- **elem kerete kilóg a widgetből** (4): ALL largest+widest ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (2): Shown=on ×2
- **rajz kilóg a widgetből** (2): ALL largest+widest ×2
- **szöveg kilóg a saját keretéből** (15): ALL largest+widest ×13, Layout.scale=1.5 ×1, Text.letters=10 ×1

## trueTone
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3
- **elem kerete kilóg a widgetből** (14): ALL largest+widest ×10, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (5): ALL largest+widest ×5

## upNext
- **Élő teszt:** Élőben: 4×1 méretben Padding = 24 → az app ÖSSZEOMLIK (TimeKinds.swift:348), minden indításkor újra.
- **Nincs látható hatása:**
  - `eventList`: Size=L (auto), Size=S (auto)
  - `widget`: Accent=red (auto)

## uptime
- **Élő teszt:** Custom gombra „Running Cool” → „Running C…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.points=96 (cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.case=lowercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.duration=abbreviated (auto/cust), Format.duration=narrow (auto/cust), Format.duration=positional (auto/cust), Format.temperature=fahrenheit (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×7, ALL largest+widest ×5, ALL sizes L ×1
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3

## voiceMemos
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust)
- **elem eltűnik** (15): Layout.padding=24 + scale 1.5 ×10, Layout=button ×3, Layout.padding=24 ×1, Layout.scale=1.5 ×1
- **elem kerete kilóg a widgetből** (12): ALL largest+widest ×8, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (3): Layout.padding=24 + scale 1.5 ×2, Layout.scale=0.5 ×1
- **rajz kilóg a widgetből** (4): ALL largest+widest ×4

## volume
- **Élő teszt:** Custom gombra „Muted” → „Mut…”.
- **Nincs látható hatása:**
  - `levelIcon`: Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `levelSlider`: Colour.track (auto/cust), Line.ends=butt (auto/cust), Line.ends=square (auto/cust), Line.fillEnd colour (auto/cust), Line.fillStyle=gradient (auto/cust), Line.thickness=1 (auto/cust), Line.thickness=16 (auto/cust), Line.track=0 (auto/cust), Line.track=1 (auto/cust)
  - `levelValue`: Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Format.percentDecimals=2 (auto/cust), Layout.scale=1.5 (cust), Layout=slider (auto)
- **elem eltűnik** (10): Layout.padding=24 + scale 1.5 ×10
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout=ring ×2, ALL largest+widest ×2, Layout.padding=24 + scale 1.5 ×1
- **keret 6×4 pt alá zsugorítható** (6): resize topLeading in 1000pt ×1, resize topTrailing in 1000pt ×1, resize leading in 1000pt ×1, resize trailing in 1000pt ×1, resize bottomLeading in 1000pt ×1, resize bottomTrailing in 1000pt ×1

## wifi
- **Nincs látható hatása:**
  - `controlButton`: Colour.secondary (auto/cust), Size=L (auto), Size=S (auto), Symbol.filled=off (auto/cust), Symbol.filled=on (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=palette (auto/cust)
  - `controlName`: Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust), Text.wording (auto/cust)
  - `controlStatus`: Text.alignment=center (auto/cust), Text.alignment=trailing (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (cust)
  - `widget`: Layout.scale=1.5 (cust)
- **elem eltűnik** (12): Layout.padding=24 + scale 1.5 ×9, Layout=button ×3
- **elem kerete kilóg a widgetből** (16): ALL largest+widest ×12, Text.points=96 ×4
- **szem ikonnal rejtve is látszik (custom)** (2): Eye=off (custom) ×2
- **elemek átfedik egymást** (5): Layout.padding=24 + scale 1.5 ×3, Layout.scale=0.5 ×1, Layout.scale=1.5 ×1
- **rajz kilóg a widgetből** (7): ALL largest+widest ×6, Text.points=96 ×1

## worldClock
- **Élő teszt:** Custom gombra „Cupertino” → „Cuperti…”.
- **Nincs látható hatása:**
  - `label`: Text.lines=2 (auto), Text.lines=3 (auto), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `symbol`: Symbol.filled=off (auto/cust), Symbol.rendering=hierarchical (auto/cust), Symbol.rendering=multicolor (auto/cust), Symbol.rendering=palette (auto/cust)
  - `value`: Font.design=rounded (auto/cust), Font.italic=on (auto/cust), Text.case=lowercase (auto/cust), Text.case=uppercase (auto/cust), Text.lines=2 (auto), Text.lines=3 (auto), Text.points=96 (cust), Text.tooLong=head (auto/cust), Text.tooLong=middle (auto/cust), Text.tooLong=shrink (auto/cust)
  - `widget`: Accent=red (auto/cust), Layout.scale=1.5 (cust), Stack.alignment=bottomTrailing (auto), Stack.alignment=topLeading (auto), Stack.direction=horizontal (auto), Stack.direction=vertical (auto), Stack.spacing=0 (auto), Stack.spacing=24 (auto)
- **elem eltűnik** (13): Layout.padding=24 + scale 1.5 ×7, ALL largest+widest ×6
- **szem ikonnal rejtve is látszik (custom)** (3): Eye=off (custom) ×3
