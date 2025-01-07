///|
trait ToJs {
  to_js(Self) -> String
}

///|
pub impl ToJs for @kernel.Kernel with to_js(self : @kernel.Kernel) -> String {
  let content = StringBuilder::new()
  content.write_string(
    #|const isNode = typeof process !== "undefined";
    #|
    #|const adapter = await navigator.gpu.requestAdapter();
    #|
    #|if (!adapter) {
    #|  throw new Error("WebGPU not supported");
    #|}
    #|
    #|const device = await adapter.requestDevice();
    #|
    #|async function onMessage(event) {
    #|  const { data, args } = event;
    #|}
    ,
  )
  ...
}
