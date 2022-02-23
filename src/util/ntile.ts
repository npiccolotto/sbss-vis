import { SpatialSummaryCellValue } from "@/types/store";

export function isNotEmpty(pct: SpatialSummaryCellValue): pct is number {
  if (Number.isFinite(pct)) {
    return true;
  }
  return false;
}

export function ntileToRotation(pct: SpatialSummaryCellValue) {
  if (isNotEmpty(pct)) {
    return pct <= 3 ? 0 : 180;
  }
  return 0;
}

export function ntileToSize(pct: SpatialSummaryCellValue) {
  if (isNotEmpty(pct)) {
    if (pct >= 3 && pct <= 4) {
      return 1;
    }
    if (pct == 2 || pct == 5) {
      return 2;
    }
    return 3;
  }
  return 0;
}

export function getIconIndexForPercentile(pct: number, set: number) {
  return set * 6 + pct;
}
export function getIconUrlForPercentile(iconIndex: number) {
  return `${process.env.VUE_APP_PUBLIC_PATH}images/icons_${iconIndex}.png`;
}
