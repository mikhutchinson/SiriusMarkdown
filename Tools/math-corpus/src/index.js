import { readFileSync } from "node:fs";
import MathJax from "@mathjax/src";
import katex from "katex";

const corpusURL = new URL("../corpus.json", import.meta.url);
const shouldCheck = process.argv.includes("--check");
const requiredGroups = Object.freeze([
  "basic",
  "fractions",
  "operators",
  "generated-ai",
  "matrices",
  "environments",
  "relations",
  "arrows",
  "accents",
  "typography",
  "sirius-compatibility",
  "diagnostics"
]);

async function main() {
  const corpus = JSON.parse(readFileSync(corpusURL, "utf8"));
  validateCorpus(corpus);

  await MathJax.init({ loader: { load: ["input/tex", "output/svg"] } });
  let compared = 0;
  let skipped = 0;

  for (const testCase of corpus.cases) {
    if (testCase.webExpected === "skip") {
      skipped += 1;
      continue;
    }

    assertEqual(testCase.webExpected, "success", `${testCase.id}: unsupported webExpected`);
    const katexHTML = renderKaTeX(testCase);
    const mathJaxSVG = await renderMathJax(testCase);
    compared += 1;

    if (shouldCheck) {
      assertIncludes(katexHTML, "katex", `${testCase.id}: KaTeX output missing katex marker`);
      assertIncludes(mathJaxSVG, "<svg", `${testCase.id}: MathJax output missing SVG`);
      rejectMathJaxErrorOutput(testCase, mathJaxSVG);
    }
  }

  const nativeImageCases = corpus.cases.filter((testCase) => testCase.nativeExpected === "image");
  console.log(
    `math corpus: ${corpus.cases.length} cases, ${nativeImageCases.length} native-image cases, ` +
      `${compared} KaTeX/MathJax parity cases, ${skipped} Sirius-only/diagnostic skips`
  );
}

function renderKaTeX(testCase) {
  try {
    return katex.renderToString(testCase.latex, {
      displayMode: testCase.display,
      throwOnError: true,
      strict: "error",
      trust: false,
      output: "htmlAndMathml"
    });
  } catch (error) {
    throw new Error(`${testCase.id}: KaTeX rejected ${JSON.stringify(testCase.latex)}: ${error.message}`);
  }
}

async function renderMathJax(testCase) {
  try {
    const node = await MathJax.tex2svgPromise(testCase.latex, { display: testCase.display });
    return MathJax.startup.adaptor.serializeXML(node);
  } catch (error) {
    throw new Error(`${testCase.id}: MathJax rejected ${JSON.stringify(testCase.latex)}: ${error.message}`);
  }
}

function rejectMathJaxErrorOutput(testCase, output) {
  if (
    output.includes("data-mjx-error") ||
    output.includes("mjx-merror") ||
    output.includes('data-mml-node="merror"') ||
    output.includes("mjx-error")
  ) {
    throw new Error(`${testCase.id}: MathJax produced error markup for ${JSON.stringify(testCase.latex)}`);
  }
}

function validateCorpus(corpus) {
  assertEqual(corpus.schemaVersion, 1, "schemaVersion");
  requireArray(corpus.requiredGroups, "requiredGroups");
  assertArrayEqual(corpus.requiredGroups, requiredGroups, "requiredGroups");
  requireArray(corpus.cases, "cases");
  requirePositiveInteger(corpus.minimumNativeImageCases, "minimumNativeImageCases");

  const seenIDs = new Set();
  const groups = new Set();
  let nativeImageCount = 0;
  let webSuccessCount = 0;
  let diagnosticCount = 0;

  for (const testCase of corpus.cases) {
    requireString(testCase.id, "case.id");
    requireString(testCase.group, `${testCase.id}.group`);
    requireString(testCase.latex, `${testCase.id}.latex`);
    requireBoolean(testCase.display, `${testCase.id}.display`);
    requireExpected(testCase.nativeExpected, ["image", "text"], `${testCase.id}.nativeExpected`);
    requireExpected(testCase.webExpected, ["success", "skip"], `${testCase.id}.webExpected`);

    if (seenIDs.has(testCase.id)) {
      throw new Error(`duplicate case id: ${testCase.id}`);
    }
    seenIDs.add(testCase.id);
    groups.add(testCase.group);

    if (testCase.nativeExpected === "image") {
      nativeImageCount += 1;
      validateVisualGolden(testCase);
    }
    if (testCase.webExpected === "success") {
      webSuccessCount += 1;
    }
    if (testCase.group === "diagnostics") {
      diagnosticCount += 1;
    }
  }

  for (const group of requiredGroups) {
    if (!groups.has(group)) {
      throw new Error(`required group is missing from corpus: ${group}`);
    }
  }

  if (nativeImageCount < corpus.minimumNativeImageCases) {
    throw new Error(`expected at least ${corpus.minimumNativeImageCases} native image cases, found ${nativeImageCount}`);
  }
  if (webSuccessCount < 35) {
    throw new Error(`expected at least 35 KaTeX/MathJax parity cases, found ${webSuccessCount}`);
  }
  if (diagnosticCount < 2) {
    throw new Error(`expected at least 2 diagnostic fallback cases, found ${diagnosticCount}`);
  }
}

function validateVisualGolden(testCase) {
  const visual = testCase.visual;
  if (typeof visual !== "object" || visual === null) {
    throw new Error(`${testCase.id}: native image case missing visual golden bounds`);
  }
  requirePositiveFiniteNumber(visual.minWidth, `${testCase.id}.visual.minWidth`);
  requirePositiveFiniteNumber(visual.maxWidth, `${testCase.id}.visual.maxWidth`);
  requirePositiveFiniteNumber(visual.minHeight, `${testCase.id}.visual.minHeight`);
  requirePositiveFiniteNumber(visual.maxHeight, `${testCase.id}.visual.maxHeight`);
  requirePositiveFiniteNumber(visual.maxDescent, `${testCase.id}.visual.maxDescent`);
  if (visual.minWidth >= visual.maxWidth) {
    throw new Error(`${testCase.id}: visual width bounds are inverted`);
  }
  if (visual.minHeight >= visual.maxHeight) {
    throw new Error(`${testCase.id}: visual height bounds are inverted`);
  }
}

function requireArray(value, name) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error(`${name} must be a non-empty array`);
  }
}

function requireString(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} must be a non-empty string`);
  }
}

function requireBoolean(value, name) {
  if (typeof value !== "boolean") {
    throw new Error(`${name} must be a boolean`);
  }
}

function requireExpected(value, allowed, name) {
  if (!allowed.includes(value)) {
    throw new Error(`${name} must be one of ${allowed.join(", ")}`);
  }
}

function requirePositiveInteger(value, name) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
}

function requirePositiveFiniteNumber(value, name) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive finite number`);
  }
}

function assertEqual(actual, expected, message) {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

function assertArrayEqual(actual, expected, message) {
  if (actual.length !== expected.length) {
    throw new Error(`${message}: expected ${expected.length} entries, got ${actual.length}`);
  }
  for (let index = 0; index < expected.length; index += 1) {
    if (actual[index] !== expected[index]) {
      throw new Error(`${message}[${index}]: expected ${expected[index]}, got ${actual[index]}`);
    }
  }
}

function assertIncludes(value, needle, message) {
  if (!value.includes(needle)) {
    throw new Error(message);
  }
}

await main();
