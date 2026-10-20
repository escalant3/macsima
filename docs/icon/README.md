# App icon

`AppIcon.svg` is the source: a dark rounded square with a faint grid and an orange-to-purple Σ. The app uses the PNGs exported from it, in `App/Macsima/Assets.xcassets/AppIcon.appiconset` (16, 32, 128, 256 and 512 points, each at 1× and 2×). `project.yml` names the set with `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.

The icon is flat: one image, with the rounded square drawn into it.

## Later: a layered icon

Make a layered version with Icon Composer (Xcode › Open Developer Tool › Icon Composer), so macOS 26 can apply Liquid Glass and the dark, tinted and clear appearances:

- Layers: the background gradient, the grid, and the Σ (its shadow stroke as a separate layer or left to the glass).
- Leave the rounded square to the system: the background fills the whole canvas.
- Check the default, dark and tinted appearances, and the small sizes (16 and 32 points).
- Add the `.icon` file to `App/Macsima`, name it in `ASSETCATALOG_COMPILER_APPICON_NAME`, and remove the `.appiconset`.

## If the Dock shows the generic icon

The first build after adding the icon showed macOS's placeholder: LaunchServices had cached the bundle without one. Quit the app, then run `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f .build/xcode/Build/Products/Debug/Macsima.app` and relaunch.
