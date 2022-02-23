import { StoreState } from "./store.d.ts";
declare module "@vue/runtime-core" {
  // Declare your own store states.
  interface State extends StoreState {}

  interface ComponentCustomProperties {
    $store: Store<State>;
  }
}
