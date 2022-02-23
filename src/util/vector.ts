export function isEqual<T>(a: T[], b: T[], compFn = (a: T, b: T) => a === b) {
  if (a === b) return true;
  if (a == null || b == null) return false;
  if (a.length !== b.length) return false;

  for (var i = 0; i < a.length; ++i) {
    if (!compFn(a[i], b[i])) return false;
  }
  return true;
}
