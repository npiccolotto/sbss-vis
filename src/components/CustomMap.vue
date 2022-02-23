<template>
  <div
    v-on:mouseenter="setActive"
    v-on:mouseleave="setInactive"
    :style="{
      width: '100%',
      height: '100%',
      border: isActiveMap ? '1px solid red' : '1px solid black'
    }"
  >
    <div
      :data-locations-hash="visibleLocationsHash"
      style="width: 100%; height:100%;"
      ref="map"
    ></div>
  </div>
</template>

<script lang="ts">
import { Vue, Prop, Component } from "vue-property-decorator";
import L from "leaflet";
import { Location } from "@/types/store";
import { isEqual } from "@/util/vector";
import { matrixToVector } from "@/util/matrix";
import { groupVariableId, hash } from "@/util/util";
import {
  getIconIndexForPercentile,
  getIconUrlForPercentile
} from "@/util/ntile";
import { latLngBoundsToArray } from "@/util/geo";

class MapClass extends Vue {
  @Prop({ default: "" }) public group!: string;
  @Prop({ default: "" }) public column!: string;

  //public zoom: number = 5;
  //public center: Location = [0, 0];
  public isActiveMap = false;
  public map: any | null = null;
  public markers: any[] = [];

  // computed
  public bounds!: [Location, Location];
  public minMaxNormValues!: number[];
  public dataset!: number[];
  public visibleLocations!: number[];
  public colIndex!: number;

  public updateMarkers() {}
}

@Component<MapClass>({
  watch: {
    numVariablesInMap: function(n, o) {
      if (n !== o) {
        console.log("map invalidated", this.$props.group, this.$props.column);
        this.map.invalidateSize(true);
      }
    },
    bounds: function(n, o) {
      console.log(
        "bounds changed",
        this.$props.group,
        this.$props.column,
        n,
        o
      );
      const currentBounds = latLngBoundsToArray(this.map.getBounds());
      if (
        !isEqual(
          matrixToVector(currentBounds),
          matrixToVector(n),
          (x, y) => Math.abs(x - y) < 0.00001
        )
      ) {
        console.log("bounds update", this.$props.group, this.$props.column);
        this.map.invalidateSize(true);
        this.map.fitBounds(n);
        this.updateMarkers();
      }
    }
  },
  computed: {
    visibleLocations: function() {
      const visibleLocations = this.$store.state.view.visibleLocations[
        groupVariableId(this.$props.group, this.column)
      ];
      return visibleLocations || [];
    },
    visibleLocationsHash: function() {
      return hash(JSON.stringify(this.visibleLocations));
    },
    numVariablesInMap: function() {
      return this.$store.state.view.variablesInMap.length;
    },
    bounds: function() {
      return this.$store.state.view.bounds;
    },
    iconUrlLocation: function() {
      return process.env.VUE_APP_PUBLIC_PATH + "images/icon-location.png";
    },
    colIndex() {
      return this.$store.getters.colIndex(
        this.$props.group,
        this.$props.column
      );
    },
    dataset: function() {
      return this.$store.state.dataset.groups[this.$props.group].ntiles[
        this.colIndex
      ];
    }
  }
})
export default class Map extends MapClass {
  mounted() {
    const tileLayers = {
      OSM: L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"),
      Satellite: L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
      ),
      OpenTopo: L.tileLayer("https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png")
    };

    const mapEl = this.$refs.map as HTMLElement;
    this.map = L.map(mapEl, {
      zoom: 0,
      center: [0, 0],
      layers: [tileLayers.OSM, tileLayers.Satellite, tileLayers.OpenTopo]
    });
    L.control.layers(tileLayers, {}).addTo(this.map);
    L.control.scale().addTo(this.map);

    this.map.on("zoomend", this.onUpdateMapViewState);
    this.map.on("moveend", this.onUpdateMapViewState);

    this.map.whenReady(() => {
      console.log("map loaded", this.$props.group, this.$props.column);
      console.log("mounted bounds", this.bounds);
      this.map.invalidateSize(true);
      this.map.fitBounds(this.bounds);
      this.markers = this.$store.state.dataset.locations.map(
        (l: any, i: number) => ({
          ...l,
          visible: false,
          obj: null,
          index: i
        })
      );
      this.updateMarkers();
    });
  }

  updated() {
    this.updateMarkers();
  }

  updateMarkers() {
    for (const m of this.markers) {
      m.visible = false;
    }
    for (const i of this.visibleLocations) {
      this.markers[i].visible = true;
    }

    this.drawMarkers();
  }

  drawMarkers() {
    // add all markers
    // TODO could be chunked or even done by web workers
    setTimeout(() => {
      for (const [i, marker] of this.markers.entries()) {
        if (!marker.visible && marker.obj !== null) {
          //console.log("hiding marker", i);
          marker.obj.remove();
          marker.obj = null;
        }
        if (marker.visible && marker.obj === null) {
          //console.log("showing marker", i);
          let v = this.dataset[i];

          const r = 8;
          const obj = L.marker(this.$store.state.dataset.locations[i], {
            icon: L.icon({
              iconUrl: getIconUrlForPercentile(getIconIndexForPercentile(v, 0)),
              iconSize: [r, r],
              iconAnchor: [r / 2, r / 2]
            }),
            title: `Original value: ${
              this.$store.state.dataset.groups[this.$props.group].original[
                this.colIndex
              ][i]
            }`
          });
          obj.addTo(this.map);
          marker.obj = obj;
        }
      }
    }, 0);
  }

  onUpdateMapViewState() {
    if (this.isActiveMap) {
      const b = latLngBoundsToArray(this.map.getBounds());
      this.$store.dispatch("setBounds", b);
    }
  }

  setActive() {
    this.isActiveMap = true;
  }
  setInactive() {
    this.isActiveMap = false;
  }
}
</script>
