///|
struct WebGPU {
  worker : Worker
}

///|
priv type Worker

///|
extern "js" fn Worker::new(source : String) -> Worker =
  #|(source) => {
  #|  let worker;
  #|  if (globalThis.Worker) {
  #|    const blob = new Blob([source], { type: "application/javascript" });
  #|    const url = URL.createObjectURL(blob);
  #|    worker = new Worker(url, { type: "module" });
  #|  } else {
  #|    const { Worker } = require("node:worker_threads");
  #|    worker = new Worker(source, { eval: true });
  #|  }
  #|  return worker;
  #|}

///|
extern "js" fn Worker::terminate(self : Worker) -> Unit =
  #|(worker) => {
  #|  worker.terminate();
  #|}

///|
priv type Js

///|
fn identity[T, U](value : T) -> U = "%identity"

///|
extern "js" fn Worker::postMessageJs(self : Worker, message : Js) -> Unit =
  #|(worker, message) => {
  #|  worker.postMessage(message);
  #|}

///|
fn Worker::postMessage[T](self : Worker, message : T) -> Unit {
  self.postMessageJs(identity(message))
}

///|
trait Sized {
  type_size() -> Int
}

///|
pub fn WebGPU::allocate[T : Sized](self : WebGPU, value : FixedArray[T]) -> Int {
  struct Message {
    size : Int
    usage : Int
    value : FixedArray[T]
  }
  self.worker.postMessage({
    size: value.length() * T::type_size(),
    usage: 0,
    value,
  })
}
