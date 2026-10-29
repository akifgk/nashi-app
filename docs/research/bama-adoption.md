# BAMA adoption for Nashi

Research date: 2026-10-27. Upstream: [daveebbelaar/bama](https://github.com/daveebbelaar/bama/tree/9b986714f248036cdf3bdf458b93cd4b67fe120f), revision `9b986714f248036cdf3bdf458b93cd4b67fe120f`, MIT.

BAMA is a development skill collection, not an application runtime. Its 21 skills were installed locally with their original category structure, supporting files and license. They are development tools; Nashi users do not need BAMA. No runtime dependency, account, analytics, new minimum OS version or replacement design system was introduced.

Evidence labels: **V** = source or runtime verified; **R** = user-review opinion, not a reproduced Nashi defect; **P** = proposal requiring more investigation.

## Decisions implemented

| Priority | Finding and decision | Acceptance evidence |
| --- | --- | --- |
| P1 | **V:** Existing CLI, native gesture tests and conversion checks already cover substantial behavior. Add a permission-free UI audit beside them, rather than replace them. | The same ten scene IDs, two themes and two languages on Mac and Windows; generated fixtures; readiness checks; machine-readable failures; isolated preferences and Library. See [UI audit guide](../testing/UI-AUDIT.md). |
| P1 | **V:** Custom trim handles needed semantic controls. Expose independent Start and End sliders to macOS accessibility and Windows UI Automation. | Stable identifiers and element identity, editable values, dynamic boundaries, increment/decrement, disabled behavior, invalid/crossing input tests, and existing pointer-handler regressions. |
| P1 | **V:** Library artwork previously called system icon providers from UI construction. Move file metadata/icon work off the UI thread, deduplicate simultaneous requests and cache bounded results. | Tests cover eight concurrent requests, warm reuse, changed/deleted/recreated files, LRU eviction and stale asynchronous completion. Windows shell extraction uses a background STA worker and frozen images. |

The audit uses production views, not recreated mockups. Its initial scope is Home, selected input, Library, General/Formats/Updates settings, multiple-PDF wheel, Crop, Annotate and Frame. Other tools retain their existing functional tests. A render audit is not proof of every tool or every real keyboard, mouse or screen-reader interaction.

## Market and review evidence

| Product | Verified reference | Implication for Nashi |
| --- | --- | --- |
| Dropover | **V:** [Official App Store listing](https://apps.apple.com/us/app/dropover-easier-drag-drop/id1355679052?mt=12): file shelf, Quick Look, shortcuts and system integration. **R:** [2024 discussion](https://www.reddit.com/r/macapps/comments/1da6x2d/dropover_best_in_class/) values the daily shelf workflow; some users report crowded menus or conversion problems. | Keep Float and common file actions quick; validate focus, layout and output quality. Reviews are dated opinions, not current verified bugs. |
| Clop | **V:** [Official product site](https://lowtechguys.com/clop/): local optimization, automation, batch operations and CLI. **R:** [User discussion](https://www.reddit.com/r/macapps/comments/1lh2jyk/), [PDF quality report](https://www.reddit.com/r/macapps/comments/1sw0651/blurry_pdf_in_clop/), [color-profile discussion](https://www.reddit.com/r/macapps/comments/1qf9nma/clop_optimisation_of_picture_changes/) show demand for dependable output and visible quality tradeoffs. | Preserve originals, verify dimensions/color/quality and measure cancellation/progress. Do not infer a current competitor defect from an older report. |
| Dropzone 5 | **V:** [Official site](https://aptonic.com/) and [release notes](https://aptonic.com/releasenotes): Drop Bar, custom actions, CLI and shortcut integration. **R:** [Launch discussion](https://www.reddit.com/r/macapps/comments/1s1i0ze/dropzone_5_is_here/) values custom actions while some prefer simpler shelf workflows. | Shared command semantics and drag/browser regressions matter more than adding an unrelated launcher. |
| Tangerine | **V:** [Official product site](https://tangerineformac.com/) and [App Store listing](https://apps.apple.com/us/app/tangerine-file-converter/id6813034065?mt=12): radial drag interaction and broad conversion/tool coverage. Independent review evidence is comparatively limited. | Preserve Nashi's radial workflow and platform parity; prioritize reliability and readable labels over expanding menu density. |

These are qualitative product signals, not a representative market survey. Prices and marketing counts were intentionally excluded from implementation decisions.

## Follow-up list for approval

| Priority | Proposal | Why it is separate / acceptance target |
| --- | --- | --- |
| P2 | Window-arrangement AX performance pass | Current Mac controller polls at 25 ms and performs synchronous accessibility queries. Measure real drag responsiveness first, then move bounded AX work off the UI thread and stop unnecessary idle polling without losing modifier timing. Test slow/unresponsive target apps and multiple displays. |
| P2 | Expand the audit to all editors and dependency profiles | Add media, PDF, document and unavailable-tool states, with explicit asynchronous readiness and light/dark EN/TR captures. Keep original preservation and real export checks. |
| P2 | Visual regression baselines | Store reviewed platform-specific baselines in CI; account for fonts, scale, native materials and OS differences. Current geometry/nonblank checks must not be described as pixel parity. |
| P2 | Shared command metadata | Reconcile menu, wheel, keyboard and CLI descriptions; add focus-sensitive command availability tests before considering a new live automation API. Existing stateless CLI remains useful. |
| P2 | Crop accessibility actions | Offer named move/resize/reset actions that use the production crop model, followed by VoiceOver/Narrator and keyboard tests. |
| P2 | Additional Library filesystem reads | Measure and remove remaining synchronous availability checks from row evaluation; retain missing-file feedback and bounded refresh behavior. |
| P3 | Additional Shortcuts/Services integration | Use supported APIs with availability checks and test on macOS 13. Apple distinguishes App Intents support from macOS-unavailable App Shortcuts. |
| P3 | Optional live agent interface | Only if a real use case emerges: opt-in private Unix socket/current-user named pipe, versioned commands, restricted operations and an obvious off switch. Distributed notifications alone provide no authentication. No live server was enabled here. |

Not adopted: raising minimum macOS to 26, rewriting the application, replacing the icon/brand, adding a cloud shelf or general clipboard history, deleting user saved state, changing signing/permissions, or importing promotional tooling into Nashi.

## Technical sources and boundaries

- BAMA's research, test-mac-app, performance, build-and-verify and layout-grid skills informed the workflow. Its new-app defaults were adapted to this existing Mac 13 / Windows product.
- [Apple accessibility sliders](https://developer.apple.com/documentation/appkit/nsaccessibilityslider) and [Microsoft RangeValue provider contract](https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/implementing-the-ui-automation-rangevalue-control-pattern) define semantic endpoint behavior. OS-specific invalid-value behavior is intentional: bounded native Mac setters and standard UIA rejection on Windows.
- [Microsoft SHGetFileInfo](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetfileinfow) recommends background work to avoid UI stalls. Windows extraction retains STA semantics.
- [AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) does not make synchronous UI-thread polling free; cumulative delays require measurement.
- [Apple App Shortcuts guidance](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts) prevents treating new-platform templates as Mac 13-compatible integration.

Performance probes use an injected slow icon provider to establish UI-queue isolation. They do not claim an equivalent whole-application speedup. RenderTargetBitmap/cacheDisplay proofs exclude live desktop composition and native chrome; Computer Use complements them.
