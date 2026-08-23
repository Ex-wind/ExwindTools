# ExwindTools

The EXWIND toolbox addon.

## Project Relationships and Localization

### Runtime Dependencies

- `ExwindTools/ExwindTools.toc` declares `RequiredDeps: ExwindCore`. Install the `ExwindCore` addon directory from [EXWINDCORE](https://github.com/Ex-wind/EXWINDCORE) alongside this addon.
- [EXBOSS](https://github.com/Ex-wind/EXBOSS) also uses EXWINDCORE. Neither EXBOSS nor ExwindTools is a required runtime dependency of the other.
- EXWINDCORE provides the shared framework and UI foundation. EXBOSS maintains its own encounter data and dedicated locale packs.

### Localization

- Shared locale entry point: [EXWINDCORE / ExwindCore/Locale/Init.lua](https://github.com/Ex-wind/EXWINDCORE/blob/main/ExwindCore/Locale/Init.lua)
- All shared locale files: [EXWINDCORE / ExwindCore/Locale](https://github.com/Ex-wind/EXWINDCORE/tree/main/ExwindCore/Locale)
- Built-in core notice text: [ExwindToolsCoreNotice/LargePanel.lua](ExwindToolsCoreNotice/LargePanel.lua)
- EXBOSS-specific locale packs: [EXBOSS / EXBOSS-Locale](https://github.com/Ex-wind/EXBOSS/tree/main/EXBOSS-Locale)
