# LinguaPDF — lector de PDF para aprender idiomas

App Flutter (Android + iOS) para leer PDFs en otro idioma. **Mantén el dedo sobre una palabra** y
aparece un cuadro encima con:

- la traducción de la palabra **según la frase** en la que está,
- botón 🔊 de pronunciación (voz del sistema),
- traducción de la frase completa ("Frase en contexto") y botón para escucharla,
- botón 🔖 para guardarla en tu **Vocabulario**.

## Funciones

| Función | Detalle |
|---|---|
| Biblioteca | Importa PDFs, recuerda la página por la que vas y muestra el progreso |
| Traducción offline | Google ML Kit en el dispositivo (gratis, sin internet tras descargar el idioma, ~30 MB/idioma). La palabra se traduce *dentro de su frase* (se marca con `[ ]` y se extrae del resultado) |
| Diccionario offline EN→ES | ~69.000 palabras y 117.000 formas flexionadas de Wiktionary: todos los significados, categoría gramatical, IPA, forma base (*went → go*) y phrasal verbs (*break down*). Se resalta el significado que encaja con la frase |
| Traducción con IA (opcional) | Con una API key de Anthropic en Ajustes: Claude elige el significado exacto en el contexto, detecta phrasal verbs/expresiones, da forma base, categoría gramatical y una explicación. Si falla, vuelve a la traducción offline |
| Idiomas | Inglés, español, francés, alemán, italiano, portugués, neerlandés, catalán, ruso, japonés, chino, coreano. Detección automática del idioma del libro |
| Pronunciación | Motor TTS del sistema, velocidad ajustable |
| Tema | Claro / oscuro / según el sistema (botón rápido en la biblioteca). Páginas del PDF: automático, normal, sepia o noche |

## Estructura

```
lib/
  main.dart                     Arranque + temas claro/oscuro
  core/languages.dart           Idiomas soportados (ML Kit + locale TTS)
  reader/
    reader_screen.dart          Visor (pdfrx), barras, modos de página
    word_locator.dart           Posición del dedo -> palabra + frase (con coordenadas de cada carácter)
    translation_popup.dart      Cuadro emergente con traducción, audio y guardar
  screens/                      Biblioteca, vocabulario, ajustes
  services/                     Traducción, TTS, ajustes, biblioteca, vocabulario
```

## Compilar (Windows)

```powershell
$env:Path = "D:\Android\flutter\bin;" + $env:Path
cd D:\Android\lingua_pdf
flutter build apk --release --split-per-abi
```

El APK para móviles actuales queda en `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
(Está firmado con la clave de depuración: válido para instalar y probar. Para Google Play hay que crear
una clave de firma propia.)

## Regenerar el diccionario

```powershell
curl.exe -L -o D:\Android\descargas\wiktionary\kaikki-English.jsonl.gz https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl.gz
python -I tools\build_dictionary.py D:\Android\descargas\wiktionary\kaikki-English.jsonl.gz assets\dict\en_es.db
```

Después sube `_version` en `lib/services/dictionary_service.dart` para que los móviles copien la nueva base.
Datos: Wiktionary (CC BY-SA 4.0) vía wiktextract/kaikki.org — ver `assets/dict/LICENSE.txt`.

## iPhone sin Mac

Compilar para iOS requiere macOS + Xcode, pero no hace falta tener un Mac propio:

1. **Codemagic** (codemagic.io) o **GitHub Actions** con máquinas macOS en la nube compilan este
   mismo proyecto y generan el `.ipa`.
2. Para instalarlo en un iPhone, Apple exige firmarlo:
   - **Apple Developer Program** (99 $/año): instalación por TestFlight o App Store. Es la vía recomendada.
   - Con un Apple ID gratuito y **Sideloadly/AltStore** desde Windows: funciona, pero la app caduca cada 7 días.

El código ya está preparado para iOS (carpeta `ios/`, iOS 15.5+ por ML Kit, `ios/Podfile`); no hay que reescribir nada.

### Paso a paso con GitHub Actions (gratis)

1. Crea una cuenta en github.com y un repositorio **público** (los Mac son gratis en repos públicos;
   en privados hay ~200 min/mes de macOS gratis, y cada compilación gasta unos 15–25 min × 10).
2. Sube el proyecto:
   ```powershell
   cd D:\Android\lingua_pdf
   git init
   git add .
   git commit -m "LinguaPDF"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/lingua_pdf.git
   git push -u origin main
   ```
3. En GitHub: pestaña **Actions → iOS (.ipa) → Run workflow**. Al terminar (~15 min) descarga
   `LinguaPDF-ios` en la sección *Artifacts* → dentro está `LinguaPDF-unsigned.ipa`.
4. Instálalo en el iPhone desde Windows con **Sideloadly** (sideloadly.io): conecta el iPhone por USB,
   arrastra el `.ipa`, pon tu Apple ID y pulsa *Start*. En el iPhone: Ajustes → General → VPN y gestión
   de dispositivos → confiar en tu Apple ID, y activa el **Modo desarrollador** (Ajustes → Privacidad).
   Con Apple ID gratuito hay que reinstalar cada 7 días (Sideloadly puede refrescarlo automáticamente).
