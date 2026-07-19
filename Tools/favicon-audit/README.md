# Runtime favicon audit

`SiriusMarkdownFaviconAudit` exercises the exact package resolver against live
public origins. It does not use a bundled favicon set or a third-party favicon
proxy. Each result is either a natively validated site icon or the same safe
generic glyph the renderer displays when a site does not expose a usable icon.

Run the reproducible consumer-site corpus:

```sh
swift run SiriusMarkdownFaviconAudit \
  --input Tools/favicon-audit/curated-popular-domains.txt \
  --report /tmp/siriusmarkdown-favicon-audit.json \
  --concurrency 16 \
  --limit 125
```

The input accepts either one domain per line or `rank,domain` CSV. For a broad
independent ranking, download a current Tranco list, extract its CSV, and pass
the desired prefix to the same command. Live results are intentionally not a
release assertion: sites change redirects, bot defenses, HTML, icons, and
availability. The deterministic unit suite owns security and correctness; this
tool exposes real-world compatibility and the reasons behind every fallback.

Do not weaken network policy to increase the favicon count. A generic glyph is
the correct result for authentication walls, challenges, missing icons,
private/special endpoints, invalid image bytes, or responses outside the
configured bounds.
