export default class AttestReporter {
  onTestCaseResult(testCase) {
    const result = testCase.result();
    const names = [];
    for (let p = testCase.parent; p && p.type === "suite"; p = p.parent) {
      names.unshift(p.name);
    }
    names.push(testCase.name);
    process.stderr.write(
      `${JSON.stringify({
        type: "attest:test",
        names,
        file: testCase.module.moduleId,
        location: testCase.location,
        state: result.state,
        mode: testCase.task.mode,
        duration: testCase.diagnostic()?.duration,
        errors: (result.errors ?? []).map((e) => ({ message: e.message, stack: e.stack })),
      })}\n`,
    );
  }
}
