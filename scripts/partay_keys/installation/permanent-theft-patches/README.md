# Permanent Theft Garage Patches

ParTay Keys keeps the original legal owner in the normal vehicle owner column and uses `possession_id` for active stolen possession. Some garage resources must be patched so their garage lists, store checks, and retrieval checks respect that active possession.

Use only the file for the garage resource installed on your server:

- [Qbox](qbox.md)
- [JG Advanced Garages](jg-advancedgarages.md)

These patches are only needed when `Config.Heist.EnablePermanentTheft = true`.
