export type PodwatchError = {
  _tag:
    | "ValidationError"
    | "ConflictError"
    | "NotFoundError"
    | "InfrastructureError";
  message: string;
};

export const validationError = (message: string): PodwatchError => ({
  _tag: "ValidationError",
  message,
});

export const conflictError = (message: string): PodwatchError => ({
  _tag: "ConflictError",
  message,
});

export const notFoundError = (message: string): PodwatchError => ({
  _tag: "NotFoundError",
  message,
});

export const infrastructureError = (message: string): PodwatchError => ({
  _tag: "InfrastructureError",
  message,
});

export const formatPodwatchError = (error: unknown): PodwatchError => {
  if (
    typeof error === "object" &&
    error !== null &&
    "_tag" in error &&
    "message" in error &&
    typeof error.message === "string"
  ) {
    return error as PodwatchError;
  }

  if (error instanceof Error) {
    return infrastructureError(error.message);
  }

  return infrastructureError("Unexpected server failure.");
};
