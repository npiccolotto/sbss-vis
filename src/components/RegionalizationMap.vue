<template>
  <div
    :style="{
      width: '100%',
      height: '100%'
    }"
  >
    <div
      style="display: grid; grid-template-columns: max-content 1fr repeat(2, max-content); grid-gap: 5px;"
    >
      <div class="btn-group" role="group" aria-label="Data Source">
        <button
          type="button"
          @click="dataSource = 0"
          :class="{
            btn: true,
            'btn-light': dataSource === 1,
            'btn-primary': dataSource === 0
          }"
        >
          Precomputed
        </button>
        <button
          title="Copy precomputed to custom"
          :class="{
            btn: true,
            'btn-secondary': true
          }"
          @click="copyGuidanceFocusToUserData"
        >
          &rarr;
        </button>
        <button
          @click="dataSource = 1"
          type="button"
          :class="{
            btn: true,
            'btn-light': dataSource === 0,
            'btn-primary': dataSource === 1
          }"
        >
          Custom
        </button>
      </div>
      <div></div>
      <div
        style="display: flex;flex-direction: column;"
        v-if="$store.state.view.guidanceEnabled"
      >
        <small>Show Custom Features</small>
        <select v-model="userFeatureInMap">
          <option v-for="f in availableFeatures" :key="f" :value="f">{{
            f
          }}</option>
        </select>
      </div>
      <div style="display: flex;flex-direction: column;">
        <small>Show Points</small>
        <label>
          <select v-model="pointsInMap">
            <option v-for="f in availablePoints" :key="f" :value="f">{{
              f
            }}</option>
          </select>
        </label>
      </div>
    </div>
    <div
      ref="map"
      :data-foo="guidanceFocus"
      :style="{
        width: '100%',
        height: '90%'
      }"
    ></div>
  </div>
</template>

<script lang="ts">
import {
  KernelGuidance,
  Location,
  RegionGuidance,
  StoreState
} from "@/types/store";
import L, { GeoJSONOptions, PathOptions } from "leaflet";
import * as turf from "@turf/turf";
import "@geoman-io/leaflet-geoman-free";
import { Vue, Component } from "vue-property-decorator";
import {
  donuts,
  latLngBoundsToArray,
  latLngsToArray,
  latLngToArray,
  matchPolygons
} from "@/util/geo";
import chunk from "lodash/chunk";
import {
  getIconIndexForPercentile,
  getIconUrlForPercentile
} from "@/util/ntile";
import { forEachPair } from "@/util/util";
import { isEqual } from "@/util/vector";
import { matrixToVector } from "@/util/matrix";

function geoJSONPropsToLeafletStyle(
  props: Partial<{
    fill: string;
    "fill-opacity": number;
    stroke: string;
    "stroke-opacity": number;
    "stroke-width": number;
  }>,
  defaults: PathOptions
): PathOptions {
  const ret = { ...defaults };
  if (props.fill) {
    ret.fill = true;
    ret.fillColor = props.fill;
    if (props["fill-opacity"]) {
      ret.fillOpacity = props["fill-opacity"];
    }
  }

  if (props.stroke && props["stroke-width"] && props["stroke-width"] > 0) {
    ret.stroke = true;
    ret.color = props.stroke;
    if (props["stroke-width"]) {
      ret.weight = props["stroke-width"];
    }
  }

  return ret;
}

enum EditMode {
  OFF = 0,
  MERGE_REGION = 1,
  SPLIT_REGION = 2,
  DRAW_KERNEL = 3
}

enum DataSource {
  GUIDANCE = 0,
  USER = 1
}

class MapClass extends Vue {
  public map: any | null = null;

  public maxBounds!: [Location, Location];
  public dataSource: DataSource = DataSource.GUIDANCE;

  // Polygons of all regions
  public regionsPolygons: turf.helpers.Feature<
    turf.helpers.Polygon,
    turf.helpers.Properties
  >[] = [];
  // The leaflet layers of said polygons
  public regionsPolygonsLayer: any[] = [];

  // Polygons of all kernels
  public kernelFCs: turf.helpers.FeatureCollection<
    turf.helpers.Polygon,
    turf.helpers.Properties
  >[] = [];
  // The leaflet layers of said polygons
  public kernelFCsLayer: any[] = [];

  // edit mode stuff
  public editModeType: EditMode = EditMode.OFF;
  public polysToMerge: number[] = [];

  public kernelCenter: any;
  public kernelExtents: number[] = [];
  public kernelExtentsLayer: any[] = [];
  public kernelModeClickCount: number = 0;

  public userFeatureInMap: string = "none";
  public userFeatureLayer!: any;
  public pointsInMap: string = "none";
  public pointsLayer!: any;

  public regionsData!: RegionGuidance[];
  public kernelData!: KernelGuidance[];
  public kernelModeEnabled!: boolean;
  public mergeModeEnabled!: boolean;
  public splitModeEnabled!: boolean;

  public showData() {}
  public showUserFeature(feature: string) {}
  public updatePoints(which: string) {}
}

const GEOJSON_KERNEL_STYLE: PathOptions = {
  stroke: true,
  weight: 0.25,
  color: "black",
  fill: true,
  fillColor: "gray",
  opacity: 0.75
};

const GEOJSON_REGION_STYLE: PathOptions = {
  weight: 1,
  stroke: true,
  color: "black",
  fill: true,
  fillColor: "transparent"
};

const GEOJSON_USRFT_STYLE: PathOptions = {
  stroke: false,
  fill: true,
  fillColor: "blue"
};

/**
 * RegionalizationMap
 *
 * A map component in which you build regionalizations.
 *
 */

@Component<MapClass>({
  watch: {
    dataSource: function(n, o) {
      if (n !== o) {
        this.showData();
      }
    },
    userFeatureInMap: function(n, o) {
      if (n !== o) {
        this.showUserFeature(n);
      }
    },
    pointsInMap: function(n, o) {
      if (n !== o) {
        this.updatePoints(n);
      }
    },
    bounds: function(n, o) {
      console.log("bounds changed", n, o);
      const currentBounds = latLngBoundsToArray(this.map.getBounds());
      if (
        !isEqual(
          matrixToVector(currentBounds),
          matrixToVector(n),
          (x, y) => Math.abs(x - y) < 0.00001
        )
      ) {
        this.map.invalidateSize(true);
        this.map.fitBounds(n);
      }
    }
  },
  computed: {
    bounds: function() {
      return this.$store.state.view.bounds;
    },
    availableFeatures: function() {
      return ["none", ...Object.keys(this.$store.state.userFeatures)];
    },
    availablePoints: function() {
      let colnames: string[] = [];
      if ((this.$store.state as StoreState).dataset.groups.param) {
        colnames = (this.$store.state as StoreState).dataset.groups.param
          .colnames;
      }
      return ["none", "locations-only", ...colnames];
    },

    mergeModeEnabled: function() {
      return this.editModeType === EditMode.MERGE_REGION;
    },
    splitModeEnabled: function() {
      return this.editModeType === EditMode.SPLIT_REGION;
    },
    kernelModeEnabled: function() {
      return this.editModeType === EditMode.DRAW_KERNEL;
    },
    maxBounds: function() {
      return (this.$store.state as StoreState).dataset.locationsBBoxes.wgs84;
    },
    guidanceFocus: function() {
      return this.$store.getters.guidanceFocus();
    },
    regionsData: function() {
      const state = this.$store.state as StoreState;
      const strategy = state.view.parameterInput.focusActiveStrategy;
      if (this.dataSource === DataSource.GUIDANCE) {
        if (!state.view.parameterInput.focus[strategy]) {
          return [];
        }
        const regioLevel = state.view.parameterInput.focus[strategy]
          ?.regionalizationLevel!;
        const regions = state.guidance[strategy].regions[regioLevel];
        return regions;
      }
      if (this.dataSource === DataSource.USER) {
        return state.view.parameterInput.userInput.regions;
      }
    },
    kernelData: function() {
      const state = this.$store.state as StoreState;
      if (this.dataSource === DataSource.GUIDANCE) {
        const guidanceKernel = this.$store.getters.guidanceFocus().kernel;
        return guidanceKernel ? [guidanceKernel] : [];
      } else {
        if (this.dataSource === DataSource.USER) {
          return state.view.parameterInput.userInput.kernels;
        }
      }
    }
  }
})
export default class RegionalizationMap extends MapClass {
  mounted() {
    const mapEl = this.$refs.map as HTMLElement;
    const tileLayers = {
      // TODO replace apikey with your own
      Landscape: L.tileLayer(
        "https://tile.thunderforest.com/landscape/{z}/{x}/{y}.png?apikey=7c352c8ff1244dd8b732e349e0b0fe8d"
      ),
      Satellite: L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
      ),
      OpenTopo: L.tileLayer("https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png"),
      OSM: L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png")
    };

    this.map = L.map(mapEl, {
      attributionControl: false,
      zoom: 0,
      center: [0, 0],
      layers: [
        tileLayers.Landscape,
        tileLayers.OSM,
        tileLayers.Satellite,
        tileLayers.OpenTopo
      ]
    });
    L.control.layers(tileLayers, {}).addTo(this.map);
    L.control.scale().addTo(this.map);
    this.map.pm.setGlobalOptions({ snappable: false });
    this.map.pm.addControls({
      position: "topleft",
      drawPolyline: true,
      drawCircle: false,
      removalMode: false,
      cutPolygon: false,
      dragMode: false,
      editMode: process.env.NODE_ENV !== "production",
      drawRectangle: false,
      drawCircleMarker: false,
      drawMarker: false,
      drawPolygon: false
    });

    this.map.pm.setGlobalOptions({ snappable: true });

    this.map.on("pm:create", this.onDrawEnd);
    this.map.on("pm:buttonclick", this.onButtonClick);

    this.map.on("zoomend", this.onUpdateMapViewState);
    this.map.on("moveend", this.onUpdateMapViewState);

    this.map.pm.Toolbar.createCustomControl({
      name: "merge",
      title: "Merge Polygons",
      block: "draw",
      className: "icon-merge"
    });
    this.map.pm.Toolbar.createCustomControl({
      name: "kernel",
      title: "Define kernels",
      block: "custom",
      className: "icon-kernel"
    });

    this.map.whenReady(() => {
      this.map.invalidateSize(true);
      this.map.fitBounds(this.maxBounds);
    });
  }

  copyGuidanceFocusToUserData() {
    this.$store.dispatch("copyGuidanceFocusToUserData");
  }

  makeKernelsForRegions(
    regionsAsTurfPolys: turf.helpers.Feature<turf.helpers.Polygon>[],
    kernels: KernelGuidance[]
  ) {
    const kernelRings = kernels.flatMap(k => k.ring);
    // bb = [[maxX, minX],[maxY,minY]]
    const outerMostBBox = this.$store.getters.bbox();
    const outerMostBBoxPoly = this.$store.getters.bboxPolygon();
    return regionsAsTurfPolys.map(r => {
      const center = turf.center(r);
      const nuts = donuts(center, kernelRings);
      const allButThisRegion = turf.difference(
        outerMostBBoxPoly,
        r
      ) as turf.helpers.Feature<turf.helpers.Polygon>;
      // go through all donuts
      // for each donut, clip all OTHER regions away from it
      const clipped = turf.featureReduce(
        nuts,
        // TODO the clipping is a nice idea but only works for rectangles
        // when a region is any simple polygon we'll need to write a custom
        // clip function i guess
        (agg: turf.helpers.Feature<turf.helpers.Polygon>[], dn) => {
          // idea: take outermost poly, cut this region out, use remainder to clip donut
          let c: null | turf.helpers.Feature<turf.helpers.Polygon> = dn;
          c = turf.bboxClip(dn, outerMostBBox) as turf.helpers.Feature<
            turf.helpers.Polygon
          >;
          if (c !== null && allButThisRegion !== null) {
            c = turf.difference(c, allButThisRegion) as turf.helpers.Feature<
              turf.helpers.Polygon
            > | null;
            if (c === null) {
              return agg;
            }
          }
          return [...agg, c];
        },
        []
      );
      return turf.featureCollection(clipped);
    });
  }

  showData() {
    const regionsAsTurfPolys = this.regionsData
      .map(r => r.patch)
      .map((patch, i) => turf.polygon([patch], {}, { id: i }));

    const kernels = this.makeKernelsForRegions(
      regionsAsTurfPolys,
      this.kernelData
    );
    this.updateRegions(regionsAsTurfPolys);
    this.updateKernels(kernels);
  }

  updated() {
    this.showData();
  }

  canBePartOfMerge(feature: turf.helpers.Feature<turf.helpers.Polygon>) {
    if (this.polysToMerge.length === 0) {
      return true;
    }
    let can = true;
    for (const polyIdx of this.polysToMerge) {
      const poly = this.regionsPolygons[polyIdx];
      if (turf.booleanDisjoint(poly, feature)) {
        can = false;
        break;
      }
    }
    return can;
  }

  hideRegions() {
    this.regionsPolygonsLayer.forEach(l => this.map.removeLayer(l));
  }

  showRegions() {
    this.regionsPolygonsLayer.forEach(l => l.addTo(this.map));
  }

  hideKernelCenter() {
    this.map.removeLayer(this.kernelCenter);
  }
  showKernelCenter() {
    this.kernelCenter.addTo(this.map);
  }
  hideKernels() {
    this.kernelFCsLayer.forEach(l => this.map.removeLayer(l));
  }

  showKernels() {
    this.kernelFCsLayer.forEach(l => l.addTo(this.map));
  }
  onMapClick(event: any) {
    if (this.kernelModeEnabled) {
      if (this.kernelModeClickCount === 0) {
        if (this.kernelCenter) {
          this.hideKernelCenter();
          this.resetKernelExtents();
        }
        const r = 8;
        this.kernelCenter = L.marker(event.latlng, {
          icon: L.icon({
            iconUrl:
              process.env.VUE_APP_PUBLIC_PATH + "/images/icon-location.png",
            iconSize: [r, r],
            iconAnchor: [r / 2, r / 2]
          })
        });
        this.showKernelCenter();
        this.map.on("mousemove", this.onMapMouseMove);
      } else {
        // extent
        const center = turf.point(
          latLngToArray(this.kernelCenter.getLatLng(), false)
        );
        const pointOnCircle = turf.point(latLngToArray(event.latlng, false));
        const radius = turf.distance(center, pointOnCircle, {
          units: "kilometers"
        });
        this.kernelExtents.push(radius);
      }
      this.kernelModeClickCount += 1;
      return;
    }
  }

  hideKernelExtents() {
    this.kernelExtentsLayer.forEach(l => this.map.removeLayer(l));
  }

  showKernelExtents() {
    this.kernelExtentsLayer.forEach(l => l.addTo(this.map));
  }

  resetKernelExtents() {
    this.kernelModeClickCount = 0;
    this.kernelExtents = [];
    this.kernelExtentsLayer = [];
  }

  updateKernelExtents(
    center: turf.helpers.Feature<turf.helpers.Point>,
    extents: number[]
  ) {
    this.hideKernelExtents();
    this.kernelExtentsLayer = [
      L.geoJSON(donuts(center, extents), ({
        snapIgnore: true,
        style: GEOJSON_KERNEL_STYLE
      } as unknown) as GeoJSONOptions<any>)
    ];
    this.showKernelExtents();
  }

  onMapMouseMove(event: any) {
    if (this.kernelModeEnabled) {
      const center = turf.point(
        latLngToArray(this.kernelCenter.getLatLng(), false)
      );
      const pointOnCircle = turf.point(latLngToArray(event.latlng, false));
      const radius = turf.distance(center, pointOnCircle, {
        units: "kilometers"
      });

      let extents = [0, ...this.kernelExtents, radius];
      const kernels: KernelGuidance[] = chunk(extents, 2).map((ring, i) => {
        return {
          ring: ring as [number, number],
          type: "kernel",
          num_points: [],
          diff_ev: [],
          depth: -1,
          index: i,
          region_depth: -1
        };
      });
      this.$store.dispatch("setUserData", {
        kernels
      });
      if (extents.length % 2 == 1) {
        extents = [...extents, radius + 1];
      }
      this.updateKernelExtents(center, extents);
    }
  }

  toggleMode(type: EditMode) {
    if (this.editModeType === type) {
      this.editModeType = EditMode.OFF;
    } else {
      this.editModeType = type;
    }
  }

  onButtonClick(event: any) {
    const oldSource = this.dataSource;
    this.dataSource = DataSource.USER;

    const switchedSource = this.dataSource !== oldSource;

    if (event.btnName === "merge") {
      this.toggleMode(EditMode.MERGE_REGION);
      if (this.mergeModeEnabled) {
        this.hideKernels();
      } else {
        this.showData();
      }
    }
    if (event.btnName === "drawPolyline") {
      this.toggleMode(EditMode.SPLIT_REGION);
      if (this.splitModeEnabled) {
        this.hideKernels();
      } else {
        this.showData();
      }
    }
    if (event.btnName === "kernel") {
      this.toggleMode(EditMode.DRAW_KERNEL);
      if (this.kernelModeEnabled) {
        this.hideKernels();
        this.map.on("click", this.onMapClick);
      } else {
        this.map.off("mousemove", this.onMapMouseMove);
        this.map.off("click", this.onMapClick);
        let extents = [0, ...this.kernelExtents];
        if (extents.length % 2 === 1) {
          extents = extents.slice(-1);
        }
        this.hideKernelExtents();
        this.hideKernelCenter();
        this.resetKernelExtents();

        const kernels: KernelGuidance[] = chunk(extents, 2).map((ring, i) => {
          return {
            ring: ring as [number, number],
            type: "kernel",
            num_points: [],
            diff_ev: [],
            depth: -1,
            index: i,
            region_depth: -1
          };
        });
        this.$store.dispatch("setUserData", {
          kernels,
          __fetch__: true
        });
        this.showData();
      }
    }
  }

  onLayerMouseOver(
    feature: turf.helpers.Feature<turf.helpers.Polygon>,
    layer: any
  ) {
    if (this.mergeModeEnabled && this.canBePartOfMerge(feature)) {
      layer.setStyle({ fill: true, fillColor: "#00ff00" });
    }
  }
  onLayerMouseOut(
    feature: turf.helpers.Feature<turf.helpers.Polygon>,
    layer: any
  ) {
    if (
      this.mergeModeEnabled &&
      this.polysToMerge.indexOf(feature.id as number) >= 0
    ) {
      // leave it
    } else {
      // reset
      layer.setStyle(GEOJSON_REGION_STYLE);
    }
  }
  onLayerClick(
    feature: turf.helpers.Feature<turf.helpers.Polygon>,
    layer: any
  ) {
    if (this.mergeModeEnabled && this.canBePartOfMerge(feature)) {
      if (this.polysToMerge.length == 0) {
        layer.setStyle({ fillColor: "#00ff00" });
        this.polysToMerge = [feature.id as number];
      } else {
        // do the merge
        this.polysToMerge = [...this.polysToMerge, feature.id as number];
        this.mergePolygons();
      }
    }
  }

  mergePolygons() {
    const [firstIdx, secondIdx] = this.polysToMerge;
    this.polysToMerge = [];

    const first = this.regionsPolygons[firstIdx];
    const second = this.regionsPolygons[secondIdx];

    const otherPolys = this.regionsPolygons.filter(
      (p, i) => [firstIdx, secondIdx].indexOf(i) === -1
    );

    const merged = turf.union(first, second) as turf.helpers.Feature<
      turf.helpers.Polygon
    >;
    const polys = [...otherPolys, merged];
    polys.forEach((p, i) => (p.id = i));
    this.updateRegions(polys, true);
    this.updateKernels(this.makeKernelsForRegions(polys, []));
  }

  // TODO no recursive hole cutting (example: concentric circles from inside out)
  // TODO normalize polygons - too slow in client with binary turf.union. converting to topojson first could be a solution, or server side merging
  onDrawEnd(event: any) {
    // DrawEnd event from geoman
    // We only allow lines
    if (event.type !== "pm:create" || event.shape !== "Line") {
      return;
    }
    type LineStringCoordinates = turf.helpers.Position[];
    type PolygonCoordinates = LineStringCoordinates[];
    const newPolyCoords: PolygonCoordinates[] = [];

    // The line that was drawn
    const divider = turf.lineString(
      latLngsToArray(event.layer.getLatLngs(), false)
    );
    // Remove drawn line
    this.map.removeLayer(event.layer);

    // We go through every polygon of the multiPolygon and check if there were
    // exactly 2 intersection points with the drawn line
    // if so, we split the polygon
    for (const poly of this.regionsPolygons) {
      const polyCoords = poly.geometry.coordinates;
      const intersectionPoints = turf.lineIntersect(
        divider,
        turf.polygon([polyCoords[0]]) // Only check exterior!
      );
      if (intersectionPoints.features.length == 2) {
        // How to actually split?
        // 1) offset the divider line a little
        const offsetDivider = turf.lineOffset(divider, 1, {
          units: "meters"
        });
        // 2) connect offset to the original divider line to form a polygon
        const dividerPoly = turf.polygon([
          [
            ...divider.geometry!!.coordinates!,
            ...offsetDivider.geometry!!.coordinates.reverse(),
            divider.geometry!!.coordinates[0]
          ]
        ]);
        // 3) use turf.difference to do the split
        const newPolys = turf.difference(poly, dividerPoly)!;

        // 4) problem: coords of the two new polys are slightly offset and not contiguous
        //    it's a problem because we cannot just call turf.union on them again to merge
        const [a, b] = newPolys.geometry!.coordinates as PolygonCoordinates[];
        const aPoly = turf.polygon(a);
        const bPoly = turf.polygon(b);
        newPolyCoords.push(
          ...[aPoly.geometry.coordinates, bPoly.geometry.coordinates]
        );
      } else if (
        // No boundary intersections but line is inside the polygon
        intersectionPoints.features.length == 0 &&
        divider.geometry.coordinates.length > 2 &&
        turf.booleanContains(poly, divider)
      ) {
        // holes are not working correctly
        /* const coords = [
          ...divider.geometry.coordinates,
          divider.geometry.coordinates[0]
        ];
        const hole = turf.polygon([coords]);
        const punctured = turf.difference(poly, hole) as turf.helpers.Feature<
          turf.helpers.Polygon
        >;
        newPolyCoords.push(hole.geometry.coordinates);
        newPolyCoords.push(punctured?.geometry.coordinates); */
        newPolyCoords.push([...polyCoords]);
      } else {
        newPolyCoords.push([...polyCoords]);
      }
    }
    const polys = newPolyCoords.map((c, i) => turf.polygon(c, {}, { id: i }));
    forEachPair(polys, (a, b) => matchPolygons(a, b));
    this.updateRegions(polys, true);
    this.updateKernels(this.makeKernelsForRegions(polys, []));
    this.showData();
  }

  updateKernels(
    turfKernels: turf.helpers.FeatureCollection<turf.helpers.Polygon>[]
  ) {
    this.hideKernels();

    this.kernelFCs = turfKernels;
    this.kernelFCsLayer = this.kernelFCs.map(k =>
      L.geoJSON(k, ({
        snapIgnore: true,
        onEachFeature: (_: any, layer: L.Path) => {
          layer.setStyle(GEOJSON_KERNEL_STYLE);
        }
      } as unknown) as GeoJSONOptions<any>)
    );

    this.showKernels();
  }

  updateRegions(
    turfPolys: turf.helpers.Feature<turf.helpers.Polygon>[],
    fetchGuidance = false
  ) {
    this.hideRegions();

    // if the data source is USER then we need to persist their configuration
    if (this.dataSource === DataSource.USER && fetchGuidance) {
      const regions: RegionGuidance[] = turfPolys.map((tp, i) => {
        const patch = tp.geometry.coordinates[0];
        return {
          patch: patch as Location[],
          type: "region",
          depth: -1,
          index: i,
          // turf/projection can only project WGS84<->Mercator and our flat CRS is Web Mercator
          // so uh ok. the user regions are supposed to be shown flat to the right of the map
          // so somewhere i need to do web mercator projection
          // this could help: https://github.com/proj4js/proj4js
          patch_flat: [],
          // num points i reasonably could compute in client
          num_points: 0,
          // but for these there's a http request involved anyhow, esp. for kernels
          diff_ev: 0,
          diff_cov: 0
        };
      });
      this.$store.dispatch("setUserData", {
        regions,
        __fetch__: true
      });
    }

    this.regionsPolygons = turfPolys;
    this.regionsPolygonsLayer = this.regionsPolygons.map(p =>
      L.geoJSON(p, {
        style: GEOJSON_REGION_STYLE,
        onEachFeature: (
          feature: turf.helpers.Feature<turf.helpers.Polygon>,
          layer: any
        ) => {
          layer.on(
            "mouseover",
            this.onLayerMouseOver.bind(null, feature, layer)
          );
          layer.on("mouseout", this.onLayerMouseOut.bind(null, feature, layer));
          layer.on("click", this.onLayerClick.bind(null, feature, layer));
        }
      })
    );

    this.showRegions();
  }

  showUserFeature(feature: string) {
    if (feature === "none") {
      // actually hide shit
      if (this.userFeatureLayer) {
        this.map.removeLayer(this.userFeatureLayer);
      }
      this.showData();
      this.showKernels();
      return;
    }
    this.hideKernels();
    const featureData = (this.$store.state as StoreState).userFeatures[feature];
    this.userFeatureLayer = L.geoJSON(featureData, {
      onEachFeature: (feature, layer: L.Path) => {
        layer.setStyle(
          geoJSONPropsToLeafletStyle(feature.properties, GEOJSON_USRFT_STYLE)
        );
      }
    });
    this.userFeatureLayer.addTo(this.map);
  }

  updatePoints(which: string) {
    //hide points
    if (this.pointsLayer) {
      this.map.removeLayer(this.pointsLayer);
    }
    if (which === "none") {
      this.showData();
      this.showKernels();
      return;
    }
    const state = this.$store.state as StoreState;
    const locations = state.dataset.locations;
    const locationIcon =
      process.env.VUE_APP_PUBLIC_PATH + "images/icon-location.png";
    if (which === "locations-only") {
      const r = 12;
      //show markers for all locations
      this.pointsLayer = L.layerGroup(
        locations.map(l =>
          L.marker(l, ({
            snapIgnore: true,
            icon: L.icon({
              iconUrl: locationIcon,
              iconSize: [r, r],
              iconAnchor: [r / 2, r / 2]
            })
          } as unknown) as GeoJSONOptions<any>)
        )
      );
    } else {
      const r = 8;
      const colidx = this.$store.getters.colIndex("param", which);
      this.pointsLayer = L.layerGroup(
        locations.map((l, i) =>
          L.marker(l, ({
            snapIgnore: true,
            icon: L.icon({
              iconUrl: getIconUrlForPercentile(
                getIconIndexForPercentile(
                  state.dataset.groups.param.ntiles[colidx][i],
                  0
                )
              ),
              iconSize: [r, r],
              iconAnchor: [r / 2, r / 2]
            })
          } as unknown) as GeoJSONOptions<any>)
        )
      );
    }
    this.pointsLayer.addTo(this.map);
  }

  onUpdateMapViewState() {
    const b = latLngBoundsToArray(this.map.getBounds());
    this.$store.dispatch("setBounds", b);
  }
}
</script>

<style lang="less">
.icon-kernel {
  background-image: url(data:image/png;base64,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);
}
.icon-merge {
  background-image: url(data:image/png;base64,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);
}
</style>
