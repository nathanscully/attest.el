const stack = [];

const failure = (error) => {
  const cause = error?.cause;
  const inner = cause && typeof cause === "object" ? cause : error;
  const message =
    inner?.message ?? (typeof cause === "string" ? cause : error?.message) ?? "test failed";
  return { message, stack: inner?.stack ?? "" };
};

const state = (type, data) =>
  data.skip ? "skipped" : data.todo ? "todo" : type === "test:fail" ? "failed" : "passed";

export default async function* neotestReporter(source) {
  for await (const { type, data } of source) {
    if (type === "test:start") {
      stack.length = data.nesting;
      stack[data.nesting] = data.name;
    } else if (
      (type === "test:pass" || type === "test:fail") &&
      data.file &&
      !data.file.endsWith(data.name)
    ) {
      yield `${JSON.stringify({
        type: "neotest:test",
        kind: data.details?.type === "suite" ? "namespace" : "test",
        names: [...stack.slice(0, data.nesting), data.name],
        file: data.file,
        location: { line: data.line, column: data.column },
        state: state(type, data),
        duration: data.details?.duration_ms,
        errors: type === "test:fail" ? [failure(data.details?.error)] : [],
      })}\n`;
    }
  }
}
