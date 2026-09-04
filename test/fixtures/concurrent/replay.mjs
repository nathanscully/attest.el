import { createInterface } from "node:readline";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

const reporter = (await import(pathToFileURL(resolve(process.argv[2])))).default;

async function* events() {
  for await (const line of createInterface({ input: process.stdin })) {
    if (line.trim()) yield JSON.parse(line);
  }
}

for await (const out of reporter(events())) process.stdout.write(out);
