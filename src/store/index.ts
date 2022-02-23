import Vue from "vue";
import Vuex, { ActionContext } from "vuex";
import _axios from "axios";
import {
  StoreState,
  Location,
  DataGroup,
  SpatialSummaryGroup,
  RegionGuidance,
  KernelGuidance,
  Density
} from "@/types/store";
import { groupVariableId } from "@/util/util";
import { unboxObject } from "@/util/api";
import * as turf from "@turf/turf";
import booleanIntersects from "@turf/boolean-intersects";
import { newMatrix } from "@/util/matrix";
import { bboxToCoordinates } from "@/util/geo";
import omit from "lodash/omit";
import take from "lodash/take";

function unboxDensity(apiDensity: any): Density {
  return unboxObject(apiDensity, ["bw", "n"]);
}

function unboxRegionalizations(apiData: any) {
  return apiData.regions.map((regionalization: any, depth: number) =>
    regionalization.map((region: any) => {
      let uboxed = {
        depth,
        ...unboxObject(region, ["id", "index", "depth"])
      };
      uboxed = {
        ...uboxed,
        ...unboxObject(region.region_guidance, [
          "type",
          "num_points",
          "diff_ev",
          "diff_cov"
        ])
      };
      return uboxed;
    })
  );
}
function unboxKernels(apiData: any) {
  return (apiData.kernels || []).map((kernels: any, region_depth: number) =>
    kernels.map((ring: any) => ({
      region_depth,
      ...unboxObject(ring, ["type", "index", "depth"])
    }))
  );
}

function trackedAsyncAction<T = any>(
  fn: (ctx: ActionContext<StoreState, StoreState>, payload: T) => void
) {
  return async function(
    ctx: ActionContext<StoreState, StoreState>,
    payload: T
  ) {
    ctx.dispatch("incInflightRequests");
    try {
      await fn.call(null, ctx, payload);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
    } finally {
      ctx.dispatch("decInflightRequests");
    }
  };
}

Vue.use(Vuex);
const axios = _axios.create({
  baseURL: process.env.VUE_APP_API_URL,
  timeout: 15 * 60_000,
  responseType: "json"
});

const DEFAULT_STATE: StoreState = {
  inflightRequests: 0,
  results: {},
  view: {
    guidanceEnabled: true,
    parameterInput: {
      focusActiveStrategy: "equal-area",
      focus: {
        "equal-area": {
          regionIndex: 0,
          regionalizationLevel: 0,
          kernelDepth: 0,
          kernelIndex: 0
        },
        "cov-diff": {
          regionIndex: 0,
          regionalizationLevel: 0,
          kernelDepth: 0,
          kernelIndex: 0
        },
        user: {
          regionIndex: 0,
          regionalizationLevel: 0,
          kernelDepth: 0,
          kernelIndex: 0
        }
      },
      userInput: { kernels: [], regions: [] },
      minNumPoints: 0
    },
    variablesInMap: [],
    locationDensity: 0.1,
    center: [12, 53],
    visibleLocations: {},
    bounds: [
      [-10, -10],
      [10, 10]
    ],
    zoom: 5
  },
  guidance: {
    user: {
      regions: [],
      kernels: []
    },
    "equal-area": {
      regions: [],
      kernels: []
    },
    "cov-diff": {
      regions: [],
      kernels: []
    }
  },
  spatialSummaries: {},
  userFeatures: {},
  dataset: {
    locations: [],
    locationsBBoxes: {
      wgs84: [
        [0, 0],
        [0, 0]
      ],
      flat: [
        [0, 0],
        [0, 0]
      ]
    },

    distances: { bw: 0, n: 0, density: [] },
    groups: {}
  }
};

export default new Vuex.Store({
  strict: false,
  state: DEFAULT_STATE,
  getters: {
    initialized: state => () => {
      return (
        !!state.dataset.locations.length &&
        state.dataset.groups.param &&
        state.dataset.groups.input &&
        !!state.guidance["equal-area"].kernels.length &&
        !!state.guidance["cov-diff"].kernels.length
      );
    },
    guidanceFocus: state => (strategy?: string) => {
      const actualStrategy =
        strategy || state.view.parameterInput.focusActiveStrategy;
      if (!["equal-area", "cov-diff", "user"].includes(actualStrategy)) {
        return {};
      }
      const {
        regionalizationLevel,
        regionIndex,
        kernelDepth,
        kernelIndex
      } = state.view.parameterInput.focus[actualStrategy];
      const guidance = state.guidance[actualStrategy];
      if (!guidance || !guidance.kernels.length || !guidance.regions.length) {
        return { region: undefined, kernel: undefined };
      }
      const kernel = guidance.kernels[regionalizationLevel].find(
        k => k.depth === kernelDepth && k.index === kernelIndex
      );
      const region = guidance.regions[regionalizationLevel].find(
        r => r.index === regionIndex
      );
      return { kernel, region };
    },
    userKernels: state => () =>
      state.view.parameterInput.userInput.kernels.map(k => ({
        r0: k.ring[0],
        r1: k.ring[1]
      })),
    inputVarsInMap: state => () =>
      state.view.variablesInMap.filter(([g]) => g == "input").map(([, c]) => c),
    bboxAspectRatio: state => (crs = "wgs84") => {
      const [[b, l], [t, r]] = state.dataset.locationsBBoxes[crs]!;
      return (r - l) / (t - b);
    },
    bbox: state => (crs = "wgs84") => {
      const [[b, l], [t, r]] = state.dataset.locationsBBoxes[crs]!;
      return [l, b, r, t];
    },
    bboxPolygon: state => (crs = "wgs84") => {
      const [[b, l], [t, r]] = state.dataset.locationsBBoxes[crs]!;
      return turf.polygon([
        [
          [l, b],
          [r, b],
          [r, t],
          [l, t],
          [l, b]
        ]
      ]);
    },
    colIndex: state => (group: string, column: string) => {
      return state.dataset.groups[group].colnames.indexOf(column);
    },
    viewportInSpatialSummary: state => (
      level: number,
      bounds: [Location, Location],
      group: string = "input"
    ) => {
      const [min, max] = state.dataset.locationsBBoxes.wgs84;
      const [south, east] = min;
      const [north, west] = max;
      const height = Math.abs(north - south);
      const width = Math.abs(east - west);
      const bboxPoly = turf.polygon([bboxToCoordinates(bounds, false)]);
      // We can take any summary because the calculation doesn't depend on the values, just the grid
      // Hopefully Vue is smart enough to run this only once per level/viewport combination
      const summary =
        state.spatialSummaries[group][state.dataset.groups[group].colnames[0]][
          level
        ];

      const sideLengthSummary = summary.length;
      const cellWidth = width / sideLengthSummary;
      const cellHeight = height / sideLengthSummary;

      const mask = newMatrix(sideLengthSummary, sideLengthSummary, 0);

      for (const [j, col] of summary.entries()) {
        for (const [i] of col.entries()) {
          const cellNE: Location = [
            Math.max(south, north) - j * cellHeight,
            Math.min(east, west) + i * cellWidth
          ];
          const cellSW: Location = [
            Math.max(south, north) - (j + 1) * cellHeight,
            Math.min(east, west) + (i + 1) * cellWidth
          ];
          const cellPoly = turf.polygon([
            bboxToCoordinates([cellNE, cellSW], false)
          ]);
          const intersect = booleanIntersects(bboxPoly, cellPoly);
          if (intersect) {
            mask[i][j] = 1;
          }
        }
      }
      return mask;
    }
  },
  mutations: {
    setResult(state, payload) {
      // payload: id, result
      console.log(payload.result.params.kernels);
      Vue.set(state.results, payload.id, payload.result);
    },
    setParameterInputFocus(state, payload) {
      const { strategy } = payload;
      const focus = {
        ...{},
        ...state.view.parameterInput.focus[strategy],
        ...payload.focus
      };
      Vue.set(state.view.parameterInput.focus, strategy, focus);
      state.view.parameterInput.focusActiveStrategy = strategy;
    },
    incInflightRequests(state) {
      state.inflightRequests = state.inflightRequests + 1;
    },
    decInflightRequests(state) {
      state.inflightRequests = state.inflightRequests - 1;
    },
    setVisibleLocations(state, { group, variable, locations }: any) {
      Vue.set(
        state.view.visibleLocations,
        groupVariableId(group, variable),
        locations
      );
    },
    setZoom(state, zoom) {
      state.view.zoom = zoom;
    },
    setLocationDensity(state, locationDensity) {
      state.view.locationDensity = locationDensity;
    },
    setCenter(state, center) {
      state.view.center = center;
    },
    setBounds(state, bounds) {
      state.view.bounds = bounds;
    },
    setSpatialSummary(state, { name, summary }) {
      Vue.set(state.spatialSummaries, name, summary);
    },
    setDataset(state, payload) {
      state.dataset = { ...state.dataset, ...Object.freeze(payload) };
    },
    setDataGroup(state, { group, payload }) {
      Vue.set(state.dataset.groups, group, Object.freeze(payload));
    },
    setGuidance(state, [strategy, payload]) {
      state.guidance = Object.freeze({
        ...state.guidance,
        [strategy]: payload
      }); //TODO
    },
    setUserFeatures(state, payload) {
      state.userFeatures = Object.freeze(payload);
    },
    addVariableToMap(state, [group, col]) {
      state.view.variablesInMap = [...state.view.variablesInMap, [group, col]];
    },
    removeVariableFromMap(state, [group, col]) {
      state.view.variablesInMap = state.view.variablesInMap.filter(
        ([g, c]) => !(g === group && c === col)
      );
    },
    setUserData(state, payload) {
      state.view.parameterInput.userInput = payload;
    }
  },
  actions: {
    incInflightRequests({ commit }) {
      commit("incInflightRequests");
    },
    decInflightRequests({ commit }) {
      commit("decInflightRequests");
    },
    addVariableToMap({ commit }, [group, col]) {
      commit("addVariableToMap", [group, col]);
    },
    removeVariableFromMap({ commit }, [group, col]) {
      commit("removeVariableFromMap", [group, col]);
    },
    setBounds({ commit, state, dispatch }, bounds) {
      commit("setBounds", bounds);
      for (const v of state.view.variablesInMap) {
        dispatch("fetchLocationsInViewportVariable", {
          bounds,
          group: v[0],
          variable: v[1]
        });
      }
    },
    resetViewport({ state, dispatch }) {
      dispatch("setBounds", state.dataset.locationsBBoxes.wgs84);
    },
    setUserData({ commit, dispatch, state }, payload) {
      const newUserData = {
        ...state.view.parameterInput.userInput,
        ...omit(payload, "__fetch__")
      };
      commit("setUserData", newUserData);
      if (payload.__fetch__ || false) {
        dispatch("fetchGuidanceForUserData", newUserData);
      }
    },
    copyGuidanceFocusToUserData({ dispatch, state, getters }) {
      const focus =
        state.view.parameterInput.focus[
          state.view.parameterInput.focusActiveStrategy
        ];
      if (!focus) {
        return; //?
      }
      const regions =
        state.guidance[state.view.parameterInput.focusActiveStrategy].regions[
          focus.regionalizationLevel
        ];
      const kernel = getters.guidanceFocus().kernel;
      const kernels = kernel ? [kernel] : [];
      dispatch("setUserData", { regions, kernels, __fetch__: true });
    },
    setLocationDensity({ state, commit, dispatch }, locationDensity) {
      commit("setLocationDensity", locationDensity);
      for (const [group, column] of state.view.variablesInMap) {
        dispatch("fetchLocationsInViewportVariable", {
          bounds: state.view.bounds,
          group,
          variable: column
        });
      }
    },
    setZoom({ commit, state }, zoom) {
      if (state.view.zoom !== zoom) {
        commit("setZoom", zoom);
      }
    },
    setCenter({ commit, state }, center) {
      const eps = 0.000001;
      if (
        Math.abs(state.view.center[0] - center[0]) > eps ||
        Math.abs(state.view.center[1] - center[1]) > eps
      ) {
        commit("setCenter", center);
      }
    },
    setParameterInputFocus({ commit }, payload) {
      commit("setParameterInputFocus", payload);
    },
    fetchGuidance: trackedAsyncAction(async function fetchGuidance(
      { commit },
      partitionType = "equal-area"
    ) {
      const apiData = (
        await axios.get(`/guidance`, { params: { partitionType } })
      ).data;

      const unboxedRegions = unboxRegionalizations(apiData);
      const unboxedKernels = unboxKernels(apiData);

      commit("setGuidance", [
        partitionType,
        {
          regions: unboxedRegions,
          kernels: unboxedKernels
        }
      ]);
    }),
    fetchGuidanceForUserData: trackedAsyncAction(
      async function fetchGuidanceForUserData(
        { commit },
        payload: { regions: RegionGuidance[]; kernels: KernelGuidance[] }
      ) {
        const reqBody = {
          regions: payload.regions.map(r =>
            r.patch.map(([lng, lat]) => ({ lat, lng }))
          ),
          kernels: payload.kernels.map(r => r.ring)
        };
        const apiData = (await axios.post("/user-guidance", reqBody)).data;
        const unboxedRegions = unboxRegionalizations(apiData);
        const unboxedKernels = unboxKernels(apiData);

        commit("setGuidance", [
          "user",
          {
            regions: unboxedRegions,
            kernels: unboxedKernels
          }
        ]);
      }
    ),
    fetchSpatialSummary: trackedAsyncAction(async function fetchSpatialSummary(
      { commit },
      group = "input"
    ) {
      const input = (
        await axios.get<SpatialSummaryGroup>(`spatial-summary`, {
          params: { group }
        })
      ).data;
      commit("setSpatialSummary", { name: group, summary: input });
    }),
    fetchUserFeatures: trackedAsyncAction(async function fetchUserFeatures({
      commit
    }) {
      const featureNames = (await axios.get("/data/features")).data;
      const features: { [x: string]: any } = {};
      for (const feature of featureNames) {
        const data = (await axios.get(`/data/features/${feature}`)).data;
        features[feature] = JSON.parse(data);
      }
      commit("setUserFeatures", features);
    }),
    fetchDataset: trackedAsyncAction(async function fetchDataset({ commit }) {
      const bboxes: { [x: string]: [Location, Location] } = {};
      for (const crs of ["wgs84", "flat"]) {
        let [min, max] = (
          await axios.get("/data/locations/bbox", { params: { crs } })
        ).data;
        const [bottom, left] = min,
          [top, right] = max;
        const locationsBBox: [Location, Location] = [
          [bottom, left], // min
          [top, right] //max
        ];
        bboxes[crs] = locationsBBox;
      }
      const locations = Object.freeze(
        (await axios.get<Location[]>("/data/locations")).data.map(([x, y]) => [
          y,
          x
        ])
      );
      const distances = Object.freeze(
        unboxDensity(
          (
            await axios.get("/data/metadata/density", {
              params: { group: "dataset", col: "distances" }
            })
          ).data
        )
      );
      const payload = {
        distances,
        locationsBBoxes: bboxes,
        locations
      };
      commit("setDataset", payload);
      commit("setBounds", payload.locationsBBoxes!.wgs84!);
    }),
    fetchDataGroup: trackedAsyncAction(async function fetchDataGroup(
      { commit },
      group = "input"
    ) {
      const colnames: string[] = (
        await axios.get("/data/metadata/colnames", { params: { group } })
      ).data;
      const densities: Density[] = await Promise.all(
        colnames.map(async col =>
          unboxDensity(
            (
              await axios.get(`/data/metadata/density`, {
                params: { group, col }
              })
            ).data
          )
        )
      );
      let variogs = [];
      if (group === "param") {
        variogs = (
          await axios.get("/data/metadata/variograms", {
            params: { group, bins: 40 }
          })
        ).data;
      }

      const payload: DataGroup = {
        variogs,
        stats: (
          await axios.get("/data/metadata/descriptive-stats", {
            params: { group }
          })
        ).data,
        colnames,
        ntiles: (
          await axios.get("/data/ntiles", {
            params: { group }
          })
        ).data,
        original: (
          await axios.get("/data/original", {
            params: { group }
          })
        ).data,
        correlations: (
          await axios.get("/data/metadata/correlation-matrix", {
            params: { group }
          })
        ).data,
        densities
      };
      commit("setDataGroup", { group, payload });
    }),
    fetchLocationsInViewport: trackedAsyncAction(
      async function fetchLocationsInViewport({ commit }, bounds) {
        const resp = await axios.post(`/locations/viewport`, {
          neLat: bounds[0][0],
          neLon: bounds[0][1],
          swLat: bounds[1][0],
          swLon: bounds[1][1]
        });
        commit("setVisibleLocations", {
          group: "all",
          variable: "all",
          locations: resp.data
        });
      }
    ),
    fetchLocationsInViewportVariable: trackedAsyncAction(
      async function fetchLocationsInViewportVariable(
        { commit, state },
        { bounds, group, variable }: any
      ) {
        const resp = await axios.post(`/locations/viewport-for-variable`, {
          neLat: bounds[0][0],
          neLon: bounds[0][1],
          swLat: bounds[1][0],
          swLon: bounds[1][1],
          group,
          variable,
          density: state.view.locationDensity
        });
        commit("setVisibleLocations", {
          group,
          variable,
          locations: resp.data
        });
      }
    ),
    applyParametrization: trackedAsyncAction(
      async function applyParametrization({ dispatch, state }) {
        const kernels = state.view.parameterInput.userInput.kernels.map(
          k => k.ring
        );
        const regions = state.view.parameterInput.userInput.regions.map(r =>
          r.patch.map(([lng, lat]) => ({ lat, lng }))
        );

        const apiData = (await axios.post(`/sbss`, { kernels, regions })).data;
        dispatch("fetchResults");
      }
    ),
    exportParametrization: trackedAsyncAction(
      async function exportParametrization({ commit, state }, id) {
        window.open(
          `${process.env.VUE_APP_API_URL}/sbss/${id}/export`,
          "_blank"
        );
      }
    ),
    fetchResults: trackedAsyncAction(async function fetchResults({ commit }) {
      let ids = (await axios.get(`/sbss`)).data as string[];
      ids = ids.reverse();
      for (const id of ids) {
        const result = (await axios.get(`/sbss/${id}`)).data;
        commit("setResult", {
          id,
          result: {
            params: {
              regions: unboxRegionalizations(result),
              kernels: unboxKernels(result)
            }
          }
        });
      }
    }),
    async fetchInitialData({ dispatch }) {
      await dispatch("fetchDataset");
      await dispatch("fetchDataGroup", "input");
      await dispatch("fetchDataGroup", "param");
      await dispatch("fetchSpatialSummary", "input");
      await dispatch("fetchSpatialSummary", "param");
      await dispatch("fetchGuidance", "equal-area");
      await dispatch("fetchGuidance", "cov-diff");
      await dispatch("fetchUserFeatures");
      await dispatch("fetchResults");
    }
  },
  modules: {}
});
