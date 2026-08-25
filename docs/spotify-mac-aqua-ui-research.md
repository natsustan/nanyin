# Spotify on Mac in the Aqua era: UI research (2006–2012)

Research snapshot: 2026-08-22. This is historical/design research, not a specification and not legal advice. “Aqua-era Spotify” is not one released skin: it is a useful umbrella for at least two visually distinct desktop-client families that overlapped Mac OS X Leopard, Snow Leopard, and Lion.

## Executive conclusion

The most defensible mapping is:

0. **Original design system (2006–September 2010):** Rasmus Andersson, Spotify's founding head of design, publishes the strongest surviving first-party account of the client shown in the user-provided references. He attributes the early identity and end-user client interaction design to his work, describes the desktop application as dark gray with host-native window controls and scrollbars, and explicitly frames its interaction model as obvious primary controls plus less prominent expert functionality. His page labels the work 2006–2010 and says he left Spotify in September 2010 ([Rasmus Andersson, “My work with Spotify”](https://rsms.me/work/spotify/)). Its original image files are [Desktop UI Intro](https://rsms.me/work/spotify/desktopapp.png), [Hand crafted pixels](https://rsms.me/work/spotify/handcrafted-pixels.png), and [More bits and Pieces](https://rsms.me/work/spotify/desktopui.png).

1. **Launch / early client (2008–early 2010, broadly 0.2–0.3):** a compact, dense, native-window-like dark player. It had a brushed/gradient top strip, a narrow source sidebar, persistent search, a spreadsheet-like track table, and a bottom transport/status shelf. Contemporary launch coverage dates the public service to 7 October 2008, but surviving screenshots often do not expose the build number, so “the 2008 UI” should not be presented as one precisely versioned artifact ([Spotify, ten-year retrospective](https://newsroom.spotify.com/2018-10-10/spotify-10-years-of-discovery/); [Internet Archive capture calendar for spotify.com, 2008](https://web.archive.org/web/2008/https://www.spotify.com/); [Ars Technica, 2009 review](https://arstechnica.com/information-technology/2009/01/spotify-review/)).
2. **Social/local-files client (April 2010–2011, broadly 0.4–0.6):** the same dense dark shell expanded toward an iTunes-like library model: Local Files, a larger playlist tree, social/profile surfaces, inbox and friend activity. Spotify itself described the April 2010 release as its “biggest upgrade since launch”; contemporary coverage records the social and local-library additions ([Spotify archived blog capture, 27 April 2010](https://web.archive.org/web/20100501000000/https://www.spotify.com/blog/archives/2010/04/27/spotify-redefines-the-music-experience/); [The Guardian, 27 April 2010](https://www.theguardian.com/technology/blog/2010/apr/27/spotify-social-music); [TechCrunch, 27 April 2010](https://techcrunch.com/2010/04/27/spotify-social/)).
3. **Apps / late skeuomorphic client (late 2011–2012, broadly 0.7–0.8.5):** the shell remained dark, compact, and highly textured, but the left rail gained an Apps section and the central area increasingly hosted richer app/profile pages. Spotify announced desktop Apps on 30 November 2011; a preserved Spotify Community report identifies **0.8.5.133** and includes an attached artist-page screenshot, although it was posted in 2013 and therefore is retrospective evidence ([Spotify archived Apps announcement](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/); [The Guardian, 30 November 2011](https://www.theguardian.com/technology/appsblog/2011/nov/30/spotify-apps-platform); [Spotify Community, 0.8.5.133 screenshot/report](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476)).

Accordingly, the user-provided references can now be named more precisely as the **Rasmus-era Spotify desktop design, 2006–2010**, rather than simply “Aqua Spotify.” The client used Mac window furniture, but most of its interior was custom dark Spotify chrome rather than a stock Aqua application assembled from blue pinstripes and glossy system buttons. Andersson confirms the deliberate split: standard window controls and scrollbars obeyed the host system while Spotify took “semi-conservative-but-still-daring” steps elsewhere ([Andersson](https://rsms.me/work/spotify/)). Apple’s contemporary HIG similarly distinguishes standard Aqua window/control behavior from custom controls and recommends system controls where possible ([Apple HIG, 2008 archive, “The Aqua Interface”](https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGPartIII/XHIGPartIII.html)).

## Method and confidence

Sources are ranked as follows:

* **A — first-party contemporary:** Spotify announcement/page or Apple documentation from the period.
* **B — original contemporary observation:** dated press review containing a screenshot or direct feature description.
* **C — retrospective/original artifact:** an old binary, later user screenshot, or archive catalog. Useful for build identity, but provenance and capture OS may be incomplete.
* **D — reconstruction:** modern nostalgia themes, uncited image aggregators, and memory. These can suggest search terms but do not establish history.

The Wayback links below deliberately point to timestamped captures or capture calendars. A capture proves that a page existed in archived form; it does **not** prove that every embedded image still resolves, nor that the screenshot shown was Mac rather than Windows when platform chrome is cropped. No historical binaries were executed during this research.

The three user-provided images were matched to Andersson's currently served originals by content and dimensions. On 2026-08-22 the originals measured `desktopapp.png` 640×384 (SHA-256 `673fa11248e1f7b9e49cfe9c4f07d30e7497d062ba46134973c01cbfa2c24ba6`), `handcrafted-pixels.png` 640×250 (`67fbfd5a4e97d14dd10b50c634510e152d5a2c29eca9a5229760993182d929ee`), and `desktopui.png` 640×346 (`5f7b1a6e5517f12007cbf2b013e48861878683f5bf75bd0371b95ce2f6e6d09d`). These identifiers document the research artifacts; they do not grant permission to redistribute them as production assets.

## Evidence table

| Date / likely version family | Source (level) | What it confirms | What remains uncertain |
|---|---|---|---|
| 2006–Sep 2010; founding design era | [Rasmus Andersson, “My work with Spotify”](https://rsms.me/work/spotify/) and original [desktop](https://rsms.me/work/spotify/desktopapp.png), [pixel-detail](https://rsms.me/work/spotify/handcrafted-pixels.png), and [UI-detail](https://rsms.me/work/spotify/desktopui.png) images (A, first-party designer) | The author identifies himself as Spotify's head of design from day one through Sep 2010 and claims the early brand and client interaction design. He directly documents host-native window controls/scrollbars, custom dark-gray internals, hand-crafted pixel assets, visible primary actions, quieter expert actions, resizable views, jump-to-context, queueing, and minimal settings. | The portfolio does not attach exact client build numbers or capture dates to each composite; some details span Mac, Windows, and Linux variants. |
| 7 Oct 2008; launch client, often described as 0.2-era | [Spotify ten-year retrospective](https://newsroom.spotify.com/2018-10-10/spotify-10-years-of-discovery/) (A, retrospective first-party) | Public launch date and original desktop-first product context. | No exact Mac build or full-window screenshot on this retrospective page. |
| 2008 website | [Wayback capture calendar](https://web.archive.org/web/2008/https://www.spotify.com/) (A/archive) | Contemporary Spotify web presence and period branding can be inspected capture by capture. | Website artwork is not evidence of desktop controls; embedded assets may be missing. |
| Jan 2009; early 0.3-era | [Ars Technica review](https://arstechnica.com/information-technology/2009/01/spotify-review/) (B) | Contemporary description and imagery of the early desktop service: search-led navigation, playlists, artist/album browsing, and a dense client. | Screenshot platform/build is not consistently labelled; title-bar appearance must not be used alone to claim Mac. |
| 27 Apr 2010; 0.4 generation | [Spotify archived announcement](https://web.archive.org/web/20100501000000/https://www.spotify.com/blog/archives/2010/04/27/spotify-redefines-the-music-experience/) (A/archive); [Guardian](https://www.theguardian.com/technology/blog/2010/apr/27/spotify-social-music) (B); [TechCrunch](https://techcrunch.com/2010/04/27/spotify-social/) (B) | A major client change added social profiles/activity and imported/local music while preserving Spotify’s playlist-centric desktop model. Contemporary screenshots provide cross-checkable layout evidence. | Staged rollout and auto-update mean one date does not identify every user’s exact patch build. Cropped press images may be Windows. |
| 30 Nov 2011; 0.7 generation | [Spotify archived Apps announcement](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/) (A/archive); [Guardian](https://www.theguardian.com/technology/appsblog/2011/nov/30/spotify-apps-platform) (B) | Apps lived inside the desktop client; the left navigation and central content canvas necessarily accommodated an Apps platform. | Announcement screenshots demonstrate the product family, not necessarily the final Mac production build in every market. |
| 2012–early 2013; 0.8.5 family | [Spotify Community: 0.8.5.133](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476) (C) | A user explicitly identifies build 0.8.5.133, Mac reversion steps, and an attached artist-page screenshot; also records that 0.8.8 was perceived as a substantial successor. | Post and attachment are from 2013, not a contemporaneous 2012 release record; account content and capture platform may vary. |
| 2008 Mac design context | [Apple Leopard-era HIG: Aqua interface](https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGPartIII/XHIGPartIII.html) (A) | Aqua defined standard windows, menus, controls, behaviors, consistency, and system-provided appearances; custom controls were an exception to handle carefully. | It defines the platform baseline, not Spotify’s custom colors/assets. |
| 2001/2002 Aqua lineage | [Internet Archive: Apple Aqua HIG PDF](https://archive.org/details/apple-hig) (A/archive) | Primary Apple guidance documents the older glossy Aqua vocabulary—color, transparency, animation, window layering—and standard-control rationale. | Earlier than the target period; Leopard/Snow Leopard had already reduced some early-Aqua gloss. |

## Visual anatomy across the period

### Window chrome

**Stable:** Mac screenshots should show the standard traffic-light controls and OS-managed outer window/title region, while Spotify draws a dark interior immediately beneath it. Apple’s 2008 HIG supports treating window behavior and standard furniture as Aqua, but does not make Spotify’s custom black panels “Aqua controls” ([Apple HIG](https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGPartIII/XHIGPartIII.html)).

**Early client:** the upper application strip reads as shallow metallic charcoal: subtle vertical gradient, one-pixel highlights/dividers, inset search, and small back/forward controls. It resembles contemporary pro/media applications more than candy-colored early Mac OS X. The early-client composition is visible in the contemporary Ars review ([Ars, 2009](https://arstechnica.com/information-technology/2009/01/spotify-review/)).

**2010–2012:** the outer shell remains recognizable, but more navigation and account/social controls accumulate. Apps add another first-class source category rather than replacing the shell ([Spotify Apps archive](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/)).

### Layout and sidebar

The persistent grammar is a **two-pane library window plus bottom player**:

* a narrow left source list (browse/library items, starred/local content, playlists; later people and Apps);
* a broad central content pane that alternates between track table and richer artist/profile/app pages;
* a full-width lower playback/status area.

The 2010 upgrade materially increases sidebar responsibility: local files and social navigation turn a simple playlist rail into a source tree. The 2011 Apps launch adds hosted destinations to that same hierarchy ([Guardian, 2010](https://www.theguardian.com/technology/blog/2010/apr/27/spotify-social-music); [Guardian, 2011](https://www.theguardian.com/technology/appsblog/2011/nov/30/spotify-apps-platform)). Selection is conveyed by a light/gray gradient or highlight bar rather than today’s large rounded navigation cards. Rows, separators, disclosure triangles, and tiny icons permit far more items above the fold than current Spotify.

### Track lists and information density

The canonical content surface is a compact table: single-line rows, narrow leading status/star column, text columns for title/artist/album, right-aligned duration, faint horizontal rules, and a contrasting header. This is closer to Finder/iTunes list views than a card feed. Early coverage confirms playlist/search browsing as the primary unit; the 0.8.5 report specifically praises artist pages as “clean, simple, cohesive” while noting small text ([Ars, 2009](https://arstechnica.com/information-technology/2009/01/spotify-review/); [Spotify Community, 0.8.5.133](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476)).

Album art is secondary in ordinary lists—small or absent—not the repeated large tile used by later Spotify. Rich pages grow during the Apps era, but they inhabit the central pane without erasing the dense shell ([Spotify Apps archive](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/)).

### Search

Search is globally available near the top-left/top region, visually inset like a native Aqua search field but dark-skinned. Results reuse the dense table and split metadata into scannable columns. This is an important historical discriminator: search is a persistent utility rather than a large destination page. Contemporary early review material documents search as a core entry path, while the later 0.8.5 user report explicitly says its search remained intact ([Ars, 2009](https://arstechnica.com/information-technology/2009/01/spotify-review/); [Spotify Community](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476)).

### Playback controls

Transport remains permanently available at the bottom: previous, play/pause, next clustered together; a horizontal progress scrubber and elapsed/remaining time; current-track identity/artwork; and compact volume plus shuffle/repeat controls. Controls are small, circular or beveled, and shaded to imply depth. This is skeuomorphic **micro-chrome**, not a large modern floating player. Exact ordering and whether artwork sits at far left varies across screenshots/builds, so a single ordering should not be attributed to all 2008–2012 releases without a build-labelled capture (compare the [2009 review](https://arstechnica.com/information-technology/2009/01/spotify-review/) with the [0.8.5 artifact](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476)).

### Color, texture, and typography

* **Palette:** near-black/charcoal shell, medium-gray selected states and headers, off-white primary text, muted-gray secondary text, and restrained green for brand/playback state. Period captures should be sampled individually; the current `#1DB954` brand value is not evidence for a 2009 pixel value. Spotify’s current official brand rules call Spotify Green a protected brand element, reinforcing the need not to treat today’s token as a generic historic material ([Spotify Design & Branding Guidelines](https://developer.spotify.com/documentation/design)).
* **Texture:** low-amplitude vertical gradients, bevels, inset wells, one-pixel specular lines, soft inner shadows, and occasional brushed/noisy dark surfaces. The visual effect comes from edge treatment and hierarchy, not conspicuous photographic texture. Apple described Aqua in terms of refined color, transparency and animation, while recommending standard controls for consistency ([Apple Aqua HIG archive](https://archive.org/details/apple-hig)).
* **Type:** compact system-like sans serif, regular weight for rows, bold only for headings/selected metadata, truncated single-line labels, and tight line heights. It should not be labelled with certainty as one font across 2008–2012: the rendered face depends on OS version, Spotify’s implementation, and whether a screenshot is Mac or Windows.

### Interaction density

The UI assumes mouse precision: narrow rows, small targets, right-click/context actions, drag-reorder playlists, column sorting, scrollbars, and persistent simultaneous visibility of navigation, content, and playback. The 2010 expansion favors adding sources and social surfaces into the existing desktop information architecture rather than enlarging controls ([Spotify archived 2010 announcement](https://web.archive.org/web/20100501000000/https://www.spotify.com/blog/archives/2010/04/27/spotify-redefines-the-music-experience/)). This density—not generic gloss—is the clearest transferable “period feel.”

## Changes by era

| Attribute | c. 2008–2009 | c. 2010–2011 | c. late 2011–2012 |
|---|---|---|---|
| Primary mental model | Search + playlists + catalog table | Unified streamed/local library + social graph | Same library shell + hosted Apps/richer pages |
| Left rail | Basic sources and playlists | More sources, Local Files, people/profile/inbox activity | Apps becomes a visible section; rail grows longer |
| Center | Mostly lists and compact artist/album results | Lists plus social/profile views | Lists plus app canvases and richer artist pages |
| Visual density | Very high | Very high, with more chrome | Still high; content pages begin to loosen |
| Best evidence | [Ars 2009](https://arstechnica.com/information-technology/2009/01/spotify-review/) | [Spotify archive](https://web.archive.org/web/20100501000000/https://www.spotify.com/blog/archives/2010/04/27/spotify-redefines-the-music-experience/) + [Guardian](https://www.theguardian.com/technology/blog/2010/apr/27/spotify-social-music) | [Spotify Apps archive](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/) + [0.8.5 report](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476) |

## Recommended historical baselines for a Nanyin switchable theme

These are reference candidates, not an implementation design.

### Candidate 0 — Rasmus-era desktop design, 2006–2010

**Best for:** the exact references supplied for Nanyin and the strongest source-backed first theme.

Why: this is no longer a reconstruction from press screenshots. Spotify's founding design lead directly explains the intent and publishes three original composites/detail sheets. The transferable system is specific: host-native outer controls and scrollbars; custom dark-gray multi-pane interiors; compact rows; persistent primary controls; secondary expert actions; resizable panes; contextual queue/navigation; restrained settings; and hand-crafted edge/asset treatment ([Andersson](https://rsms.me/work/spotify/)). The images also establish details missing from broader historical coverage: approximately 18–23 px source/people rows, straight gradient headers, 1 px separators, a narrow right-side people pane, a large artwork/now-playing area under the left source list, compact toggle/online states, and boxed shuffle/repeat/status controls.

For Nanyin, this should be treated as the definitive visual-behavior reference while adapting information architecture to features Nanyin actually owns. In particular, reproducing a non-functional People pane, Buy column, social sharing strip, or offline toggle would be historical theater rather than useful fidelity.

### Candidate 1 — Spotify desktop c. 2009 (early 0.3 family)

**Best for:** the clearest “compact Mac music utility” interpretation.

Why: it has the least ambiguous visual thesis—dark metallic shell, source list, persistent search, table-first content, and bottom transport—before social and Apps inflate the information architecture. It is easier to distinguish from current Spotify by structure rather than by copying brand art. The weakness is build precision: available contemporary reviews are stronger on date and composition than on exact Mac version number ([Ars, 2009](https://arstechnica.com/information-technology/2009/01/spotify-review/)). Label it **c. 2009**, not “v0.3.x exact,” until a Mac screenshot with an About box/build number and verifiable capture provenance is found.

### Candidate 2 — Spotify 0.8.5-era desktop, 2012

**Best for:** the fullest remembered late-skeuomorphic Spotify desktop.

Why: it preserves the dense dark chrome but includes the mature source tree, richer artist pages, social-era structure, and Apps-era extensibility. The build-labelled 0.8.5.133 community artifact gives a more concrete anchor than most early screenshots ([Spotify Community](https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476)); the first-party Apps announcement establishes the preceding platform change ([Spotify Apps archive](https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/)). The weakness is that the screenshot evidence is retrospective and may mix Mac/Windows interior chrome. Call it **0.8.5-era** rather than claiming pixel fidelity to every 0.8.5 Mac build.

If only one baseline is retained, the Rasmus-era source is now the clear first choice: it subsumes the cleaner c. 2009 direction and has direct design-authorship evidence. The 0.8.5-era remains a valid later theme rather than the baseline for this one.

## Trademark, icons, and proprietary assets: informational boundaries

This section is a risk checklist, not a legal conclusion.

### Lower-risk design-language borrowing

Abstract ideas and independently drawn system-like treatments are the safer reference layer: dense split-view composition, compact table rows, dark gray gradients, inset search treatment, beveled generic transport controls, divider rhythm, and period-appropriate system typography. Apple’s HIG itself encourages consistency with platform windows and controls ([Apple HIG, 2008](https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGPartIII/XHIGPartIII.html)). Use Nanyin naming and identity, generic independently created symbols, and a palette established by Nanyin rather than copied sampled assets.

### Higher-risk direct copying

Do not lift the historical Spotify wordmark, three-wave mark, application icon, proprietary sidebar glyph sheets, button bitmaps, background tiles, bundled fonts, or screenshot crops as production UI assets without an applicable permission/license. Spotify’s current first-party guidelines say an app name should not include or imply endorsement by Spotify, and an app logo should not include or resemble Spotify’s logo or brand elements (including its green/circle/waves); they also prescribe exact attribution use where Spotify metadata/content is presented ([Spotify Design & Branding Guidelines](https://developer.spotify.com/documentation/design)). Those integration rules do not grant a general right to reskin another app as Spotify.

Trademark and copyright answer different questions: the USPTO describes trademarks as words/phrases/designs identifying source, while copyright covers original works including software, photographs, and paintings ([USPTO: trademark, patent, or copyright](https://www.uspto.gov/trademarks/basics/trademark-patent-copyright)). A historic screenshot can be useful evidence while the pictured logo, album art, photography, icons, and screenshot itself may still carry separate rights. “Old” and “available in an archive” do not mean public domain.

### Practical presentation boundary

Describe a theme as “inspired by late-2000s Mac media players” or a clearly identified compatibility/history theme; avoid presenting Nanyin as an official, endorsed, or preserved Spotify client. Keep research screenshots linked to their sources rather than vendoring them as assets. Before distribution, separately review the project name, icon, store screenshots, attribution obligations for live Spotify metadata/artwork, and any exact visual assets with qualified counsel if the release posture warrants it.

## Gaps and next evidence to seek

1. **Build-labelled Mac captures:** the highest-value missing artifact is a full-window PNG plus About dialog for one early 0.3 build and one 0.4 build, with capture date and OS version.
2. **Binary provenance:** surviving DMGs can establish `CFBundleShortVersionString`, minimum OS, icon resources, and nib/resource names, but should be obtained from a checksum-bearing trusted archive and inspected statically. Generic download sites are not adequate provenance; no binaries were downloaded or run here.
3. **Mac versus Windows:** many articles crop the title bar. Interior visual claims are cross-platform-safe; traffic lights, fonts, scrollbars, and titlebar height require a clearly Mac-labelled image.
4. **Exact colors/typefaces/measurements:** web JPEGs and rescales are unsuitable for pixel sampling. Current Spotify green and current brand typography must not be projected backward.
5. **2008 launch screenshot:** Spotify’s retrospective establishes the date, but a first-party, original-resolution Mac client screenshot from October 2008 remains unlocated in the sources above.
6. **Archive fragility:** Wayback embedded media can fail independently of HTML. Preserve source URL, timestamp, caption, dimensions, and checksums if later research obtains permitted local evidence copies.

## Source index

### First-party / archival

* Rasmus Andersson, “My work with Spotify” (work labelled 2006–2010): <https://rsms.me/work/spotify/>
* Original first-party designer image, “Desktop UI Intro”: <https://rsms.me/work/spotify/desktopapp.png>
* Original first-party designer image, “Hand crafted pixels”: <https://rsms.me/work/spotify/handcrafted-pixels.png>
* Original first-party designer image, “More bits and Pieces”: <https://rsms.me/work/spotify/desktopui.png>
* Spotify, “10 Years of Discovery,” 2018: <https://newsroom.spotify.com/2018-10-10/spotify-10-years-of-discovery/>
* Spotify 2008 site capture calendar: <https://web.archive.org/web/2008/https://www.spotify.com/>
* Spotify, “Spotify redefines the music experience,” archived 2010 capture: <https://web.archive.org/web/20100501000000/https://www.spotify.com/blog/archives/2010/04/27/spotify-redefines-the-music-experience/>
* Spotify, “Say hello to Spotify Apps,” archived 2011 capture: <https://web.archive.org/web/20111202000000/http://www.spotify.com/us/blog/archives/2011/11/30/say-hello-to-spotify-apps/>
* Spotify for Developers, Design & Branding Guidelines: <https://developer.spotify.com/documentation/design>
* Apple, Leopard-era Human Interface Guidelines, “The Aqua Interface”: <https://leopard-adc.pepas.com/documentation/UserExperience/Conceptual/AppleHIGuidelines/XHIGPartIII/XHIGPartIII.html>
* Internet Archive collection containing Apple Aqua HIG material: <https://archive.org/details/apple-hig>
* USPTO, “Trademark, patent, or copyright”: <https://www.uspto.gov/trademarks/basics/trademark-patent-copyright>

### Contemporary and artifact cross-checks

* Ars Technica, “Spotify review,” January 2009: <https://arstechnica.com/information-technology/2009/01/spotify-review/>
* The Guardian, “Spotify gets social,” 27 April 2010: <https://www.theguardian.com/technology/blog/2010/apr/27/spotify-social-music>
* TechCrunch, Spotify social upgrade coverage, 27 April 2010: <https://techcrunch.com/2010/04/27/spotify-social/>
* The Guardian, Spotify Apps platform, 30 November 2011: <https://www.theguardian.com/technology/appsblog/2011/nov/30/spotify-apps-platform>
* Spotify Community, 0.8.5.133 screenshot and Mac reversion report, 2013: <https://community.spotify.com/t5/Desktop-Mac/Revert-back-to-Spotify-0-8-5-on-Mac/td-p/325476>
