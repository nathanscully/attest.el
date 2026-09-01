const serializeError = (error) =>
  error && typeof error === "object"
    ? {
        message: error.message,
        stack: error.stack,
        code: error.code,
        failureType: error.failureType,
        cause: error.cause === undefined ? undefined : serializeError(error.cause),
      }
    : error;

export default async function* neotestReporter(source) {
  for await (const event of source) {
    if (event.data?.details?.error) {
      event.data.details.error = serializeError(event.data.details.error);
    }
    yield `${JSON.stringify(event)}\n`;
  }
}
