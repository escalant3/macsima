# Localization

Macsima's interface is in English and Spanish. It follows the language macOS gives it: the system language, or the one chosen for Macsima in System Settings › General › Language & Region › Applications. There is no language setting in the app.

What is translated: menus, toolbar, sidebar panels, Settings, the find bar, status messages, undo names, Macsima's own error messages (unbalanced brackets, Maxima not starting, damaged `.wxmx` files), the warnings shown when a file has parts Macsima keeps but can't show, and the error explanations ported from wxMaxima. macOS translates its own menus (File, Edit, Window, …) and panels (Open, Save) for every language the app declares.

What is not: Maxima's output, messages and manual (Maxima prints them; Homebrew ships the English manual only), the contents of worksheets, and anything written for programs rather than people: settings keys, `.wxmx` and `.wxm` contents, what is sent to Maxima.

## How it works

- **One String Catalog for the app**, `App/Macsima/Localizable.xcstrings`, and `App/Macsima/InfoPlist.xcstrings` for the document type names in `Info.plist`. The catalog lives in the app target, not in the package. SwiftUI looks up `Text("…")`, `Button("…")` and the rest in the main bundle, so code in `MacsimaUI` needs no `bundle:` argument. `String(localized: "…")` in the kits (MaximaKit, WorksheetKit) also reads the main bundle. Under `swift test` and the command-line tools, the main bundle has no catalog, so everything is English, and the tests can compare English text.
- **Literals passed to SwiftUI are translated; `String` values are shown as they are.** `Button("Evaluate Cell")` is looked up, but `Button(title)` with a `String` variable is not. A string that reaches the screen through a variable, an enum's `title`, a status message, an undo name or an error's `description` must be made with `String(localized: "…")`. Add a `comment:` when the English alone doesn't say where it appears ("Code" as a cell kind, "Replace" as an undo name).
- **Interpolations** become format strings: `String(localized: "Exported to \(name).")` has the key `Exported to %@.`, with `%lld` for integers. Pass `String` or integers. Wrap anything else (an error, a `Duration`) in `String(describing:)`. Translations can reorder arguments with `%1$@`, `%2$lld`.
- **Plurals**: write one string with the count (`Text("\(n) cells folded")`) and give it plural variations in the catalog, not an `n == 1 ? … : …` in code.
- **Identifiers stay out**: don't compare a localized string with anything. When code needs to recognise a message, give it a constant (`MaximaSession.restartReason`).

## Keeping the catalog up to date

After adding or changing strings:

```sh
scripts/update-strings.sh
```

It builds the app into `.build/xcode-strings` with `SWIFT_EMIT_LOC_STRINGS=YES`, so the compiler lists every localizable string in the app target, MacsimaUI, MaximaKit and WorksheetKit, and merges that list into `Localizable.xcstrings` with `xcstringstool sync`. New strings come in untranslated. Strings no longer in the code are marked stale; delete them once you're sure. Xcode doesn't do this by itself, because the strings live in the package and the catalog in the app.

`swift test` (`LocalizationTests`) fails when a string has no translation, when one isn't marked translated, when a translation's placeholders differ from the English, or when a catalog has a language `project.yml` doesn't declare.

## Adding a language

1. Open `App/Macsima/Localizable.xcstrings` in Xcode, click + under the language list and pick the language. Translate every string. The editor shows each comment and where the string is used. (Editing the JSON by hand works too; copy the shape of an `es` entry.) Do the same in `InfoPlist.xcstrings`.
2. Add the language code to `CFBundleLocalizations` in `project.yml`, so macOS translates its own menus and panels too.
3. Run `swift test`. `LocalizationTests` lists anything missing.
4. Copy `Tests/Fixtures/keyscripts/l10n-es.keys` to `l10n-<code>.keys`, translate the menu title it uses (`menu Buscar y reemplazar…`), copy the `l10n-es` branch in `check.py` with your language's words, and run `Tests/Fixtures/keyscripts/run.sh l10n-<code>` after building the app. `run.sh` launches `l10n-<code>` scripts in that language (other scripts always run in English, because they find menu items by their English titles). Look at the screenshots in `.build/keyscripts/` for cut-off or awkward text.
5. Add your language's terms to the glossary below.

To try a language without changing the system: `.build/xcode/Build/Products/Debug/Macsima.app/Contents/MacOS/Macsima -AppleLanguages '(es)'`.

## Glossary

Use the same word for the same thing everywhere. Follow the platform's conventions: Apple's own translations for standard commands, and the capitalisation the language uses in macOS menus (Spanish: only the first word, "Evaluar celda").

| English | Español |
| --- | --- |
| worksheet | hoja de trabajo (hoja) |
| cell; code, text, title, section, subsection cell | celda; celda de código, de texto, de título, de sección, de subsección |
| heading | encabezado |
| input, output | entrada, salida |
| evaluate | evaluar |
| fold, unfold (sections) | plegar, desplegar |
| collapse, expand (the triangle) | contraer, expandir |
| hide, show (a cell) | ocultar, mostrar |
| watch (a variable) | vigilar |
| plot | gráfica |
| math (rendered output) | fórmula |
| debugger, step over, step into, backtrace | depurador, pasar por encima, entrar, pila de llamadas |
| interrupt, restart | interrumpir, reiniciar |
| idle (Maxima) | libre |
| kept (unknown parts of a file) | se conserva |
| archive (the `.wxmx` zip) | archivo comprimido |
| batch file | archivo por lotes |
| Find, Replace, Match Case, Use Selection for Find | Buscar, Reemplazar, Distinguir mayúsculas y minúsculas, Usar selección para buscar |
| Zoom In, Zoom Out, Actual Size | Ampliar, Reducir, Tamaño real |
| Show/Hide Sidebar | Mostrar/Ocultar barra lateral |
| font | tipo de letra |

Spanish uses "tú" (Haz clic, Escribe), Spain's vocabulary (ordenador, archivo), "app", a space before % ("100 %") and straight quotes around code characters ("(").
