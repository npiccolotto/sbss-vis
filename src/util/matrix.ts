import range from "lodash/range";

export function newMatrix<T = any>(
  rows: number,
  cols: number,
  init: T | null = null
) {
  const matrix = [];
  for (const i of range(rows)) {
    const row = [];
    for (const j of range(cols)) {
      row.push(init);
    }
    matrix.push(row);
  }
  return matrix;
}

export function matrixToVector<T = any>(M: T[][]): T[] {
  let asVector: T[] = [];
  for (const r of M) {
    asVector = [...asVector, ...r];
  }
  return asVector;
}

export function vectorToMatrix<T = any>(v: T[], sidelength: number): T[][] {
  let N: T[][] = [];
  for (let i = 1; i <= sidelength; i++) {
    N.push(v.slice((i - 1) * sidelength, i * sidelength));
  }
  return N;
}

type MoltenCell<T = any> = {
  rowIndex: number;
  colIndex: number;
  rowName: string;
  colName: string;
  value: T;
};

export function melt<T = any>(
  matrix: readonly T[][],
  rownames: string[] = range(matrix.length).map(() => "row"),
  colnames: string[] = range(matrix[0].length).map(() => "col")
): MoltenCell<T>[] {
  const result: MoltenCell<T>[] = [];
  for (let [i, row] of matrix.entries()) {
    for (let [j, col] of row.entries()) {
      result.push({
        rowIndex: i,
        rowName: rownames[i],
        colIndex: j,
        colName: colnames[j],
        value: col
      });
    }
  }
  return result;
}
