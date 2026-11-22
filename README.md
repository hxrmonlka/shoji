<h1 align=center>╋━ Shoji ˎˊ˗</h1>
<details>
<summary><b> What is this?</b></summary>
This is my Quickshell configuration! It may seem weird with the change of the naming pattern here in my projects, but worry not, it's part of <a href="https://github.com/hxrmonlka/alice/">Alice</a>.
</details>
<details>
<summary><b>Is this packaged through Lumina?</b></summary>
Not yet. There is now a command line interface <code>cli</code>, and Lumina packaging comes when it has its other components ready.
</details>
<details>
<summary><b>Can I use this?</b></summary>
Feel free bro.
</details>

---
Shoji was supposed to be a simple dynamic island but I really want an original (and productive) setup that I can rely on.
I still genuinely suck at UI stuff so... maybe help with this one.

Anyway, there isn't much I can add to this README because I still need to make a bunch of features in here.

## Runtime dependency

The lock screen password indicators use the `M3Shapes` Qt QML module from [soramanew/m3shapes](https://github.com/soramanew/m3shapes). It provides all 35 Material 3 Expressive presets, including the rounded `Triangle` and `Square` geometries. Install the module in the Qt QML import path used by Quickshell before starting Shoji.

The upstream project provides a Nix flake package named `m3shapes` and requires Qt 6.8 or newer.
