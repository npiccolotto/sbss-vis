import { Location } from "@/types/store";
import * as turf from "@turf/turf";
import chunk from "lodash/chunk";

export function bboxToCoordinates(bbox: [Location, Location], latLng = true) {
  const [min, max] = bbox;
  const [south, east] = min;
  const [north, west] = max;

  const coords: Location[] = [
    [north, east],
    [north, west],
    [south, west],
    [south, east],
    [north, east]
  ];

  return latLng ? coords : coords.map(switchLatLng);
}

export function switchLatLng(loc: Location): Location {
  return [...loc].reverse() as Location;
}

export function switchLatLngBounds(bounds: [Location, Location]) {
  return [switchLatLng(bounds[0]), switchLatLng(bounds[1])] as [
    Location,
    Location
  ];
}

type LeafletLatLng = { lat: number; lng: number };
type LeafletBounds = {
  _northEast: LeafletLatLng;
  _southWest: LeafletLatLng;
};

export function latLngToArray(leaflet: LeafletLatLng, latLng = true) {
  const { lat, lng } = leaflet;
  return latLng ? [lat, lng] : [lng, lat];
}

export function latLngsToArray(latLngs: LeafletLatLng[], latLng = true) {
  return latLngs.map(loc => latLngToArray(loc, latLng));
}

export function latLngBoundsToArray(bounds: LeafletBounds, latLng = true) {
  const arr = [
    [bounds._northEast.lat, bounds._northEast.lng],
    [bounds._southWest.lat, bounds._southWest.lng]
  ];
  if (!latLng) {
    return switchLatLngBounds(arr as [Location, Location]);
  }
  return arr;
}

export function addPropsToFeature(feat: any, properties: any) {
  return { ...feat, properties };
}

type LineString = Location[];
type Polygon = LineString[]; // As per GeoJSON RFC, first linestring is exterior, the others holes in the polygon

export function matchPolygons(
  a: turf.helpers.Feature<turf.helpers.Polygon>,
  b: turf.helpers.Feature<turf.helpers.Polygon>,
  options: { units: "meters"; distance: number } = {
    units: "meters",
    distance: 10
  }
) {
  // The idea here is to find coordinates A\B and B\A
  // If some are "close enough" (say, less than 2m distance) we make them the same coordinate
  // in order to call turf.union(a,b) later on successfully.

  // Only care about exterior
  const aPoly = getExteriorLineString(a);
  const bPoly = getExteriorLineString(b);

  const intersection: [number, number][] = [];

  for (const [i, aLoc] of aPoly.entries()) {
    for (const [j, bLoc] of bPoly.entries()) {
      if (turf.distance(aLoc, bLoc, options) <= options.distance) {
        intersection.push([i, j]);
      }
    }
  }

  for (const [aIdx, bIdx] of intersection) {
    aPoly[aIdx] = bPoly[bIdx];
  }

  return [a, b];
}

function depth(arr: any[], level = 0): number {
  if (Array.isArray(arr) && arr.length > 0) {
    return depth(arr[0], level + 1);
  }
  return level;
}

export function getExteriorLineString(
  turfFeature: turf.helpers.Feature
): number[][] {
  if (turfFeature.geometry.type === "MultiPolygon") {
    throw new Error("nope");
  }

  if (turfFeature.geometry.type === "Polygon") {
    const d = depth(turfFeature.geometry.coordinates);
    if (d === 3) {
      return (turfFeature.geometry.coordinates as number[][][])[0];
    }
    if (d === 2) {
      return turfFeature.geometry.coordinates as number[][];
    }
    throw new Error("Malformed polygon?");
  }
  throw new Error("NAYYY");
}

export function donut(
  center: turf.helpers.Feature<turf.helpers.Point>,
  radiusInner: number,
  radiusOuter: number
) {
  const circleOuter = turf.circle(center, radiusOuter, { units: "kilometers" });
  const circleInner = turf.circle(center, radiusInner, { units: "kilometers" });
  if (radiusInner >= radiusOuter) {
    return turf.featureCollection([circleInner, circleOuter]);
  }
  return turf.difference(circleOuter, circleInner) as turf.helpers.Feature<
    turf.helpers.Polygon
  >;
}

// Makes a multipolygon of several donuts
export function donuts(
  center: turf.helpers.Feature<turf.helpers.Point>,
  radii: number[] // [Ar1,Ar2,Br1,Br2...Nr1,Nr2]
) {
  let chunkedRadii = chunk(radii, 2);
  return turf.featureCollection(
    chunkedRadii.flatMap(([r1, r2]) => {
      const d = donut(center, r1, r2);
      if (d.type === "FeatureCollection") {
        return d.features;
      }
      return d;
    })
  );
}
