/**
 * Checks if the environment is Node.js.
 * @type {boolean}
 */
const isNode = typeof process !== "undefined";

/**
 * Requests a WebGPU adapter.
 * @type {GPUAdapter}
 */
const adapter = await navigator.gpu.requestAdapter();

if (!adapter) {
  throw new Error("WebGPU not supported");
}

/**
 * Requests a WebGPU device.
 * @type {GPUDevice}
 */
const device = await adapter.requestDevice();

/**
 * @typedef {Object} BufferCreateMethod
 * @property {string} type - The type of method, "buffer-create".
 * @property {number} size - The size of the buffer.
 * @property {GPUBufferUsageFlags} usage - The usage flags for the buffer.
 * @property {ArrayBuffer} [value] - Optional initial value for the buffer.
 */

/**
 * @typedef {Object} BufferGetMethod
 * @property {string} type - The type of method, "buffer-get".
 * @property {number} id - The ID of the buffer to retrieve.
 */

/**
 * @typedef {Object} BufferSetMethod
 * @property {string} type - The type of method, "buffer-set".
 * @property {number} id - The ID of the buffer to set.
 * @property {ArrayBuffer} value - The value to set in the buffer.
 */

/**
 * @typedef {BufferCreateMethod | BufferGetMethod | BufferSetMethod} Method
 */

/**
 * @typedef {Object} Message
 * @property {SharedArrayBuffer} shared - The shared array buffer for communication.
 * @property {Method} method - The method to execute.
 */

/**
 * Manages WebGPU buffers.
 */
class Manager {
  /**
   * @type {number}
   */
  buffer_id = 0;

  /**
   * @type {Map<number, GPUBuffer>}
   */
  buffers = new Map();

  /**
   * Creates a new buffer.
   * @param {Object} descriptor - The buffer descriptor.
   * @param {number} descriptor.size - The size of the buffer.
   * @param {GPUBufferUsageFlags} descriptor.usage - The usage flags for the buffer.
   * @param {ArrayBuffer} [descriptor.value] - Optional initial value for the buffer.
   * @returns {number} The ID of the created buffer.
   */
  createBuffer(descriptor) {
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

  /**
   * Retrieves the contents of a buffer.
   * @param {number} id - The ID of the buffer to retrieve.
   * @returns {Promise<ArrayBuffer>} The contents of the buffer.
   */
  async getBuffer(id) {
    const buffer = this.buffers.get(id);
    if (!buffer) {
      throw new Error(`Buffer ${id} not found`);
    }
    await buffer.mapAsync(GPUMapMode.READ);
    const bytes = new Uint8Array(buffer.getMappedRange());
    buffer.unmap();
    return bytes.buffer;
  }

  /**
   * Sets the contents of a buffer.
   * @param {number} id - The ID of the buffer to set.
   * @param {ArrayBuffer} value - The value to set in the buffer.
   */
  setBuffer(id, value) {
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

/**
 * The manager instance.
 * @type {Manager}
 */
const manager = new Manager();

/**
 * Posts an ArrayBuffer to a SharedArrayBuffer.
 * @param {SharedArrayBuffer} shared - The shared array buffer.
 * @param {ArrayBuffer} array - The array buffer to post.
 */
function postArrayBuffer(shared, array) {
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

/**
 * Handles a message.
 * @param {Message} message - The message to handle.
 */
async function handle(message) {
  const { shared, method } = message;
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
    await handle(event);
  });
}
