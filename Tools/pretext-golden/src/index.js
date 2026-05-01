import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { createCanvas } from "@napi-rs/canvas";
import { layoutWithLines, measureNaturalWidth, prepareWithSegments } from "@chenglou/pretext";

const fixturesDir = new URL("../fixtures/", import.meta.url);
const defaultFont = "16px Helvetica";
const defaultLineHeight = 18;
const tolerance = 0.5;

if (typeof globalThis.OffscreenCanvas === "undefined") {
  globalThis.OffscreenCanvas = class NodeOffscreenCanvas {
    constructor(width, height) {
      this.canvas = createCanvas(width, height);
    }

    getContext(kind) {
      return this.canvas.getContext(kind);
    }
  };
}

function loadFixtures() {
  return readdirSync(fixturesDir)
    .filter((name) => name.endsWith(".json"))
    .map((name) => {
      const file = join(fixturesDir.pathname, name);
      return JSON.parse(readFileSync(file, "utf8"));
    });
}

function main() {
  const fixtures = loadFixtures();
  if (process.argv.includes("--check") && fixtures.length === 0) {
    throw new Error("No Pretext fixtures found.");
  }

  for (const fixture of fixtures) {
    const prepared = prepareWithSegments(fixture.markdown, fixture.font ?? defaultFont, {
      whiteSpace: fixture.whiteSpace ?? "pre-wrap",
      wordBreak: fixture.wordBreak ?? "normal",
      letterSpacing: fixture.letterSpacing ?? 0
    });
    const laidOut = layoutWithLines(
      prepared,
      fixture.containerWidth,
      fixture.lineHeight ?? defaultLineHeight
    );
    const actual = {
      lineCount: laidOut.lineCount,
      naturalWidth: measureNaturalWidth(prepared),
      height: laidOut.height
    };

    if (process.argv.includes("--check")) {
      assertClose(fixture.name, "lineCount", fixture.expected.lineCount, actual.lineCount, 0);
      assertClose(fixture.name, "naturalWidth", fixture.expected.naturalWidth, actual.naturalWidth, tolerance);
      assertClose(fixture.name, "height", fixture.expected.height, actual.height, tolerance);
    }

    console.log(`${fixture.name}: ${actual.lineCount} lines, ${actual.naturalWidth.toFixed(2)}px natural`);
  }
}

function assertClose(name, field, expected, actual, fieldTolerance) {
  if (Math.abs(expected - actual) > fieldTolerance) {
    throw new Error(`${name}.${field} expected ${expected}, got ${actual}`);
  }
}

main();
