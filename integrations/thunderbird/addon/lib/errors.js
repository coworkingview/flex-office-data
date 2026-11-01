/** Error raised for a failed API call or a city slug the add-on will not send. */
export class ApiError extends Error {
  constructor(message, fields = {}) {
    super(message);
    this.name = "ApiError";
    this.status = fields.status ?? null;
    this.code = fields.code ?? "ERROR";
  }
}
