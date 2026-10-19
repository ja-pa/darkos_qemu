# dArkOS QEMU — rychlý návod

Všechny příkazy spouštěj **v Ubuntu 26.04 ve WSL2 s WSLg**, z kořene tohoto
repozitáře, jako běžný uživatel. Sudo si přípravné skripty vyžádají samy.
Pracovní data patří na linuxový filesystem v `$HOME`, mimo Git.

## 1. Spustit naše již připravené prostředí

```bash
cd ~/win_documents/ChatGPT/darkos_qemu
export WORK_DIR="$HOME/darkos-qemu-m5"
bash vm.sh es
```

`vm.sh es` otevře QEMU, počká na SSH a spustí vlastní EmulationStation.
Pokud odpovídající VM již běží, použije ji. Otevře se také legenda ovládání.
Terminál zůstane obsazený do ukončení ES; správu lze provádět z dalšího terminálu.

**V každém novém terminálu nastav stejný `WORK_DIR`.** Bez něj se používá
`~/darkos-qemu-work`, kde náš nový `images/work.qcow2` není. To byla příčina
chyby „Missing overlay“ při prvním pokusu o spuštění.

```bash
export WORK_DIR="$HOME/darkos-qemu-m5"
bash vm.sh status
bash vm.sh ssh           # interaktivní shell guestu
bash vm.sh logs          # diagnostika a konec sériového logu
# Po ukončení ES:
bash vm.sh stop          # čisté vypnutí guestu a zavření legendy
bash vm.sh check         # kontrola vypnutého qcow2
```

Další varianty:

```bash
bash vm.sh start gtk-gl               # pouze VM, bez automatického spuštění ES
bash vm.sh start serial               # VM bez grafiky; konzole jde do logu
bash vm.sh es --no-controls           # ES bez pomocného okna
bash vm.sh start gtk-gl --no-controls
bash vm.sh controls                   # otevření legendy samostatně
```

Sériovou VM před spuštěním grafického ES vypni přes `vm.sh stop`.
Legenda má dva ručně přepínané profily; zavření legendy nezastaví VM.
Mapování popisků je v [config/controls.json](config/controls.json).
Na starší instalaci hostitele lze Tkinter doplnit přes
`sudo apt-get install python3-tk`.

| Akce | EmulationStation | Game Boy / Peanut-GB |
| --- | --- | --- |
| Pohyb | Šipky | Šipky |
| Potvrzení / A | Enter | Z |
| Zpět / B | Escape | X |
| Menu / Start | Space | Enter |
| Options / Select | Tab | Backspace |
| Ukončení | F4 | Escape → návrat do ES |

Před hraním klikni do okna QEMU. U rozložení QWERTZ se může fyzická klávesa
pro Z lišit; podrobnosti jsou v [návodu pro Game Boy](docs/gameboy.md).
V ES je ověřený Game Boy s Tobu Tobu Girl a testovací OpenGL trojúhelník.

## 2. Připravit prostředí od začátku

Tuto část nepotřebuješ, pokud používáš hotové `darkos-qemu-m5` výše.
Z [původního vydání dArkOS](https://github.com/christianhaitian/dArkOS/releases#release-v01302026)
stáhni oba díly `dArkOS_RG353m_trixie_01312026.img.7z.001` a `.002`
do `images/` v repozitáři. Pak:

```bash
export WORK_DIR="$HOME/darkos-dev"
bash setup.sh source
bash sdk.sh prepare
bash build.sh build all
bash build.sh deploy all
bash vm.sh es
```

Archiv v jiném umístění lze vybrat proměnnou
`ARCHIVE=/cesta/dArkOS_RG353m_trixie_01312026.img.7z.001` před `setup.sh source`.

- `setup.sh source`: závislosti hostitele, kernel, původní image, pracovní disk
  a vlastní SSH klíč. Opakované spuštění nepřepíše existující pracovní disk.
- `sdk.sh prepare`: soukromý grafický stack a vývojové závislosti v guestu,
  následně odpovídající sysroot a SDK na hostiteli.
- `build.sh build all`: ARM64 aplikace cross-kompilované ve WSL, výchozí `JOBS=4`.
- `build.sh deploy all`: nasazení aplikací a testovací nabídky do pracovního guestu.

Příprava SDK a deploy si VM spustí a počkají na SSH. Pokud ji samy spustily,
po dokončení ji vypnou. Pokud už běžela, nechají ji běžet. Před přípravou SDK
nebo nasazením ukonči ES a ostatní grafické aplikace.

## 3. SDK a build jednotlivých aplikací

SDK obsahuje hlavičky a knihovny **Debian ARM64 guestu**, CMake toolchain,
prostředí pro pkg-config a manifest runtime. GCC/G++ 12 je na WSL hostiteli.
Samotné buildy nepotřebují spuštěnou VM; nasazení ano a zařídí si její start.

```bash
bash sdk.sh check
bash sdk.sh prepare                   # vytvoření nebo doplnění SDK
bash sdk.sh prepare --refresh         # znovu prověřit balíčky a obnovit sysroot

bash build.sh build es
bash build.sh deploy es
bash build.sh build peanut-gb
bash build.sh deploy peanut-gb
bash build.sh build sdl-demo
bash build.sh deploy sdl-demo
```

Příkaz `deploy es` zachovává nastavení, ROM a saves. Jen při záměrném návratu
k výchozímu profilu použij `bash build.sh deploy es --reset-profile`;
původní konfigurace se zálohuje. Při nesouladu SDK/runtime obnov SDK příkazem
`bash sdk.sh prepare`.

### Vlastní malá CMake aplikace

Vzor je v `demos/sdk-app`. Jeho sestavení a explicitní nasazení:

```bash
bash build.sh app demos/sdk-app
bash build.sh deploy-app "$WORK_DIR/apps/sdk-app/sdl-demo"
bash vm.sh start gtk-gl
bash vm.sh ssh 'sudo -n bash /opt/darkos-apps/sdl-demo/es-env.sh /opt/darkos-apps/sdl-demo/sdl-demo'
```

Před přímým grafickým testem ukonči ES, aby uvolnilo DRM. Pro jiný projekt použij
`bash build.sh app /cesta/k/projektu`; build vznikne v
`$WORK_DIR/apps/<název-adresáře>`. Binárku nasazuj přes `deploy-app` samostatně.
Ten ji uloží do `/opt/darkos-apps/<název-binárky>`; automaticky ji nepřidává do ES.
Pro ruční práci s nástroji SDK lze načíst `source "$WORK_DIR/sdk/environment.sh"`.

## 4. Kde najít image, binárky a logy

| Na WSL hostiteli | Obsah |
| --- | --- |
| `$WORK_DIR/images/work.qcow2` | Jediný pracovní disk pro čtyři nové vstupní skripty |
| `$WORK_DIR/images/*.img` | Původní rozbalený raw image při přípravě ze zdrojů |
| `$WORK_DIR/build/arch/arm64/boot/Image` | Kernel používaný launcherem |
| `$WORK_DIR/sdk/` | SDK, `sysroot/`, `toolchain.cmake`, `environment.sh`, manifest |
| `$WORK_DIR/repos/` | Zdrojové stromy ES a Peanut-GB |
| `$WORK_DIR/es/build/emulationstation` | Výsledek buildu ES |
| `$WORK_DIR/gb/build/peanut-sdl` | Výsledek buildu Peanut-GB |
| `$WORK_DIR/apps/sdl-demo/sdl-demo` | Demo z `build.sh build sdl-demo` |
| `$WORK_DIR/apps/sdk-app/sdl-demo` | Vzor z `build.sh app demos/sdk-app` |
| `$WORK_DIR/logs/workflow/serial.log` | Sériová konzole a chyby startu QEMU |
| `$WORK_DIR/logs/workflow/controls.log` | Chyby pomocné legendy |
| `$WORK_DIR/logs/es/`, `$WORK_DIR/logs/gb/` | Build a běhové logy jednotlivých aplikací |
| `$WORK_DIR/ssh/` | SSH identita tohoto prostředí |

V guestu jsou aplikace a data v `/opt/darkos-es`, jeho izolovaném `home/`,
`/opt/darkos-emulators/peanut-gb/{roms,saves,logs}` a `/opt/darkos-apps`.
Soukromé SDL2/Mesa knihovny jsou v `/opt/darkos-graphics`.
Po buildu aplikace vždy následuje deploy; build sám nemění obsah disku VM.

Staré milníkové disky v `~/darkos-qemu-work` zůstávají zachované. Pro běžné
používání už mezi nimi ručně nepřepínej. Další ověřená importovaná kopie je
v `~/darkos-qemu-m5-import`; při jejím použití nastav také `SSH_PORT=2233`.
Více současných prostředí musí mít odlišné disky i SSH porty.

## 5. Export a předání hotového prostředí

```bash
bash vm.sh stop
bash vm.sh export "$HOME/darkos-runtime-export"
bash sdk.sh export "$HOME/darkos-sdk-export"
```

Cílové adresáře musí být nové. Runtime export obsahuje samostatný
`runtime.qcow2` bez backing souboru, kernel `Image`, metadata, licence a kontrolní
součty. Vzniká z kopie a odstraňuje SSH identity i osobní testovací data.
SDK je samostatný export; nic se automaticky nepublikuje.

Na jiném pracovním místě, ze stejného repozitáře:

```bash
export WORK_DIR="$HOME/darkos-imported"
bash setup.sh import /cesta/darkos-runtime-export
bash sdk.sh import /cesta/darkos-sdk-export   # jen pokud chceš také kompilovat
bash vm.sh es
```

Import vytvoří vlastní pracovní disk a SSH identitu. U nás už existují ověřené
exporty `~/darkos-qemu-m5-runtime-export` (cca 5,20 GiB) a
`~/darkos-qemu-m5-sdk-export` (cca 1,40 GiB); velikosti dalších exportů se mohou lišit.

## Z čeho nyní vycházíme

- Linux 5.10.226, připnutý commit `bef65b1793524bc7bd27c4d70d0ce59cbebee032`.
- Původní dArkOS image, Debian trixie ARM64; QEMU `virt`, Cortex-A53, TCG, 1 GiB RAM.
- SDL2 2.32.4 a Mesa 25.0.7 v soukromém prefixu; KMSDRM a desktopový OpenGL
  pro ES a Peanut-GB, bez libMali/libgo2 v ověřených procesech.
- ES fork `ja-pa/EmulationStation-fcamod`, commit
  `db23162142f2d01c4c08216895fd793da243d19b`, s patchemi v tomto repozitáři.
- Peanut-GB `d0bcca771c83a2638c93a9ae61f3d51f226dc905`, testovací Tobu Tobu Girl.
- Ověřené UI, klávesnice a návrat ES → hra → ES. Audio je dummy; gamepady
  a další emulátory zatím nejsou součástí tohoto základu. Výkon není garantovaný.

Podrobnosti a dosavadní výsledky: [workflow](docs/workflow.md),
[grafika](docs/graphics.md), [EmulationStation](docs/emulationstation.md)
a [Game Boy](docs/gameboy.md). Historické důkazy jsou v `docs/evidence/`.
