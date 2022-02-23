const KM_FORMAT = new Intl.NumberFormat("en-US", {
  unit: "kilometer"
} as Intl.NumberFormatOptions);
const NR_FORMAT = new Intl.NumberFormat("en-US", {
  notation: "scientific"
} as Intl.NumberFormatOptions);

export function formatRing(ring: [number, number]) {
  return ring.map(r => KM_FORMAT.format(r)).join("–") + " km";
}

export function formatNumber(x: number) {
  return NR_FORMAT.format(x);
}
