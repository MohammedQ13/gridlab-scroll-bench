# GridLab scroll bench

A small iOS test app that mimics a 3-column, page-loaded video grid, plus UI tests that measure iOS scrolling physics under automated swipes (single flick distance, momentum from repeated flicks, throughput while pages load, swipe-vs-tap risk). Runs on an iPhone 16 Pro simulator in GitHub Actions (`.github/workflows/bench.yml`).

## Results (run 41389806206, iPhone 16 Pro simulator, Xcode on macos-15)
| Test | Result |
|---|---|
| Single flick, loaded grid (row = 178.8 pt) | 1500 pt/s: 4.9 rows · 3000: 10.0 · 5000: 16.2 · 8000: 24.6 |
| 10 flicks at 5000 pt/s | ~0.57 s apart: 637 rows · ~0.72 s: 715 · ~0.73 s: 648 · ~1.15 s: 225 (single ×10 ≈ 162) |
| Paged grid, 30 s (18/page, prefetch 6 rows) | 0.6 s page delay: 504–558 items loaded at 0.6–1.6 s flick spacing · 1.2 s delay: 324–360 |
| Swipe read as tap (20 swipes each) | 5% of screen: 20 · 10%: 0 · 20%: 0 · 45%: 0 |

Note: XCUITest gesture calls take ~0.6 s each, so the shortest real spacing tested is ~0.57 s.
