// "2026-07-01" → "July 2026". Forced to UTC so the month never shifts in
// negative-offset timezones.
export default function periodMonth(periodStart) {
  return new Date(periodStart).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}
