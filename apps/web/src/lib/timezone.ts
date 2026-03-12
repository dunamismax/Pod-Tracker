import { useEffect, useState } from "react";

export const getBrowserTimeZone = () => {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
};

export const formatInTimeZone = (isoString: string, timezone: string) =>
  new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: timezone,
    timeZoneName: "short",
  }).format(new Date(isoString));

export const useBrowserTimeZone = () => {
  const [timezone, setTimezone] = useState("UTC");

  useEffect(() => {
    setTimezone(getBrowserTimeZone());
  }, []);

  return timezone;
};
