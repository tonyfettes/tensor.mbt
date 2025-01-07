const isNode = typeof process !== "undefined";

const adapter = await navigator.gpu.requestAdapter();

if (!adapter) {
  throw new Error("WebGPU not supported");
}

const device = await adapter.requestDevice();

type Method =
  | {
      type: "buffer-create";
      size: number;
      usage: GPUBufferUsageFlags;
      value?: ArrayBuffer;
    }
  | {
      type: "buffer-get";
      id: number;
    }
  | {
      type: "buffer-set";
      id: number;
      value: ArrayBuffer;
    };

type Message = {
  shared: SharedArrayBuffer;
  method: Method;
};

class Manager {
  buffer_id: number;
  buffers: Map<number, GPUBuffer>;
  constructor() {
    this.buffer_id = 0;
    this.buffers = new Map();
  }
  createBuffer(descriptor: {
    size: number;
    usage: GPUBufferUsageFlags;
    value?: ArrayBuffer;
  }) {
    const id = this.buffer_id;
    if (descriptor.value) {
      const buffer = device.createBuffer({
        size: descriptor.value.byteLength,
        usage: descriptor.usage,
        mappedAtCreation: true,
      });
      const arrayBuffer = new Uint8Array(descriptor.value);
      const bufferMapped = buffer.getMappedRange();
      new Uint8Array(bufferMapped).set(arrayBuffer);
      buffer.unmap();
      this.buffers.set(this.buffer_id, buffer);
    } else {
      const buffer = device.createBuffer(descriptor);
      this.buffers.set(this.buffer_id, buffer);
    }
    this.buffer_id++;
    return id;
  }
  async getBuffer(id: number) {
    const buffer = this.buffers.get(id);
    if (!buffer) {
      throw new Error(`Buffer ${id} not found`);
    }
    await buffer.mapAsync(GPUMapMode.READ);
    const bytes = new Uint8Array(buffer.getMappedRange());
    buffer.unmap();
    return bytes.buffer;
  }
  setBuffer(id: number, value: ArrayBuffer) {
    const buffer = this.buffers.get(id);
    if (!buffer) {
      throw new Error(`Buffer ${id} not found`);
    }
    buffer.mapAsync(GPUMapMode.WRITE);
    const arrayBuffer = new Uint8Array(value);
    const bufferMapped = buffer.getMappedRange();
    new Uint8Array(bufferMapped).set(arrayBuffer);
    buffer.unmap();
  }
}

const manager: Manager = new Manager();

function postArrayBuffer(shared: SharedArrayBuffer, array: ArrayBuffer) {
  const offset = 2;
  const control = new Int32Array(shared, 0, offset);
  const content = new Uint8Array(shared, offset * 4, array.byteLength);
  while (Atomics.compareExchange(control, 0, 0, 1) !== 0) {
    Atomics.wait(control, 0, 1);
  }
  content.set(new Uint8Array(array));
  Atomics.store(control, 0, 2);
  Atomics.notify(control, 0, 1);
}

async function handle(message: MessageEvent<Message>) {
  const { shared, method } = message.data;
  switch (method.type) {
    case "buffer-create": {
      const id = manager.createBuffer(method);
      postArrayBuffer(shared, new Int32Array([id]));
      break;
    }
    case "buffer-get": {
      const value = await manager.getBuffer(method.id);
      postArrayBuffer(shared, value);
      break;
    }
    case "buffer-set": {
      manager.setBuffer(method.id, method.value);
      break;
    }
  }
}

if (isNode) {
  const { parentPort } = await import("node:worker_threads");
  if (!parentPort) {
    throw new Error("`parentPort` not found");
  }
  parentPort.on("message", handle);
} else {
  addEventListener("message", async (event) => {
    await handle(event as MessageEvent<Message>);
  });
}
