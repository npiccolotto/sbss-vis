type Location = [number, number];

export type SpatialSummaryCellValue = number | null;
export type SpatialSummaryLevel = SpatialSummaryCellValue[][];
type SpatialSummary = SpatialSummaryLevel[];
export type SpatialSummaryGroup = Record<string, SpatialSummary>;

type Density = {
  bw: number;
  n: number;
  density: { x: number; y: number }[];
};

type Stats = {
  ntileBorders: number[][]; // row = ntile borders of a variable
};
export type GuidanceFocus = {
  regionalizationLevel: number;
  regionIndex: number;
  kernelDepth: number;
  kernelIndex: number;
};
type ParameterInputViewState = {
  focusActiveStrategy: string;
  focus: Record<string, GuidanceFocus>;
  minNumPoints: number;
  userInput: {
    regions: RegionGuidance[];
    kernels: KernelGuidance[];
  };
};
type ViewState = {
  guidanceEnabled: boolean;
  variablesInMap: [string, string][];
  center: Location;
  locationDensity: number;
  zoom: number;
  bounds: [Location, Location];
  visibleLocations: { [x: string]: number[] }; // indices in state.locations
  parameterInput: ParameterInputViewState;
};
type VariogramValue = {
  center: number;
  value: number;
  variable: number;
};
export type DataGroup = {
  colnames: string[];
  ntiles: number[][];
  stats: Stats;
  original: number[][];
  correlations: number[][];
  densities: readonly Density[];
  variogs: readonly VariogramValue[];
};

export type Dataset = {
  locations: readonly Location[];
  locationsBBoxes: { [x: string]: [Location, Location] };
  distances: readonly Density;

  // Group is either 'input', 'param', or the ID of a SBSS result
  groups: {
    [group: string]: DataGroup;
  };
};

export type KernelGuidance = {
  type: "kernel";
  ring: [number, number];
  num_points: number[];
  diff_ev: number[];
  depth: number;
  index: number;
  region_depth: number;
};

export type RegionGuidance = {
  type: "region";
  depth: number;
  index: number;
  num_points: number;
  diff_ev: number;
  diff_cov: number;
  patch: Location[];
  patch_flat: Location[];
};

export type Guidance = {
  [strategy: string]: {
    regions: RegionGuidance[][];
    kernels: KernelGuidance[][];
  };
};

export type Result = {
  params: {
    regions: RegionGuidance[];
    kernels: KernelGuidance[];
  };
};

export type StoreState = {
  inflightRequests: number;

  view: ViewState;
  guidance: readonly Guidance;

  spatialSummaries: Record<string, SpatialSummaryGroup>;
  dataset: readonly Dataset;
  userFeatures: readonly { [x: string]: any }; // geojson
  results: Record<string, Result>;
};
