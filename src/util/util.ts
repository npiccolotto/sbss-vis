import { KernelGuidance } from "@/types/store";

export function hash(str: string, seed = 0) {
  let h1 = 0xdeadbeef ^ seed,
    h2 = 0x41c6ce57 ^ seed;
  for (let i = 0, ch; i < str.length; i++) {
    ch = str.charCodeAt(i);
    h1 = Math.imul(h1 ^ ch, 2654435761);
    h2 = Math.imul(h2 ^ ch, 1597334677);
  }
  h1 =
    Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^
    Math.imul(h2 ^ (h2 >>> 13), 3266489909);
  h2 =
    Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^
    Math.imul(h1 ^ (h1 >>> 13), 3266489909);
  return 4294967296 * (2097151 & h2) + (h1 >>> 0);
}

export function groupVariableId(group: string, variable: string) {
  return `${group}/${variable}`;
}

export function vh(v: number) {
  var h = Math.max(
    document.documentElement.clientHeight,
    window.innerHeight || 0
  );
  return (v * h) / 100;
}

export function vw(v: number) {
  var w = Math.max(
    document.documentElement.clientWidth,
    window.innerWidth || 0
  );
  return (v * w) / 100;
}

export function collect<T = any>(arr: T[], indices: number[]) {
  return indices.map(i => arr[i]);
}

export function sameKernel(k1?: KernelGuidance, k2?: KernelGuidance) {
  if (k1 === undefined || k2 === undefined) {
    return false;
  }
  return (
    k1.depth === k2.depth &&
    k1.index === k2.index &&
    k1.region_depth === k2.region_depth
  );
}

export function forEachPair<T = any>(
  arr: T[],
  iteratee: (a: T, b: T, i: number, j: number) => void
) {
  for (const [i, a] of arr.entries()) {
    for (let j = i - 1; j >= 0; j--) {
      const b = arr[j];
      iteratee(a, b, i, j);
    }
  }
}
