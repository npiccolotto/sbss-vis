import Vue from "vue";
import VueRouter, { RouteConfig } from "vue-router";
import DataLoad from "../views/DataLoad.vue";
import Explore from "../views/Explore.vue";
import Parameters from "../views/Parameters.vue";

Vue.use(VueRouter);

const routes: Array<RouteConfig> = [
  {
    path: "/",
    name: "DataLoad",
    component: DataLoad
  },
  {
    path: "/explore",
    name: "Explore",
    component: Explore
  },
  {
    path: "/new",
    name: "Parameters",
    component: Parameters
  }
];

const router = new VueRouter({
  routes
});

export default router;
