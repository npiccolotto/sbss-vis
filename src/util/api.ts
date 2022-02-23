export function unbox<T = any>(x: [T] | T[]) {
  return x[0];
}

export function unboxObject(x: any, keys: string[] = []): any {
  if (Array.isArray(x)) {
    return unbox(x as [any]);
  }
  const copy = { ...x };
  if (typeof x === "object" && x !== null) {
    for (const [k, v] of Object.entries(x)) {
      if (keys.length > 0 && keys.includes(k)) {
        copy[k] = unboxObject(v);
      }
    }
  }
  return copy;
}
