# Brand files

The mark is a results matrix: three systems by three problems, with the three
verdicts the site uses, a filled dot (verified), a hollow one (returned, not
verified or wrong) and none (no such operation). The banner adds the dot plot
of the bench pages: time per case and system on a log axis.

| File | Use |
|---|---|
| `casbench-banner.svg` (1280 x 320) | hero of the home page and of the README |
| `casbench-mark.svg` (96 px) | mark, favicon; follows light and dark |

Regenerate with `python3 -I assets/brand/gen_brand.py assets/brand`, then copy
to `site/static/brand/` (the build does not copy them: both copies are
committed, and `tools/site/test_sitegen.py` checks that they are identical).

Palette shared with the other project sites: ink `#1E2329`, off-white
`#F4F1EA`, steel `#8A949E`, accent `#F2B705`, verified `#2E9E5B`, wrong
`#D64541`. Green and red carry a verdict only, never decoration; the four
system colours of the dot plot are decoration. Licence: CC BY 4.0, like the
pages.
