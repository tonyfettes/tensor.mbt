///|
struct Tensor[T] {
  shape : Array[UInt]
  mut block : Array[UInt]?
  value : FixedArray[T]?
  graph : Graph[T]
  device : &Device
  mut buffer : Int?
} derive(Show)

///|
impl[T : Hash] Hash for Tensor[T] with hash_combine(
  self : Tensor[T],
  hasher : Hasher
) {
  for s in self.shape {
    hasher.combine_uint(s)
  }
  Hash::hash_combine(self.graph, hasher)
}

///|
impl[T : Eq] Eq for Tensor[T] with op_equal(self : Tensor[T], other : Tensor[T]) -> Bool {
  self.shape == other.shape && self.graph == other.graph
}

///|
fn Tensor::new[T](
  shape : Array[UInt],
  graph : Graph[T],
  block? : Array[UInt],
  device~ : &Device = cpu
) -> Tensor[T] {
  { shape, block, value: None, graph, device, buffer: None }
}

///|
fn Tensor::block[T](self : Tensor[T]) -> Array[UInt] {
  guard let None = self.block else { Some(block) => block }
  let block = compute_block(self.shape)
  self.block = Some(block)
  block
}

///|
enum Binary {
  Add
  Mul
} derive(Hash, Eq, Show)

///|
enum Graph[T] {
  Val(FixedArray[T])
  Get(Tensor[T])
  Binary(Binary, Tensor[T], Tensor[T])
  Reduce(Binary, Tensor[T], Int)
  Concat(FixedArray[Tensor[T]], Int)
  Expand(Tensor[T])
} derive(Eq, Show)

///|
impl[T : Hash] Hash for Graph[T] with hash_combine(
  self : Graph[T],
  hasher : Hasher
) {
  let tag_id = match self {
    Val(_) => 0
    Get(_) => 1
    Binary(_) => 2
    Reduce(_) => 3
    Concat(_) => 4
    Expand(_) => 5
  }
  hasher.combine(tag_id)
  match self {
    Val(val) =>
      for v in val {
        hasher.combine(v)
      }
    Get(x) => hasher.combine(x)
    Binary(op, a, b) => {
      hasher.combine(op)
      hasher.combine(a)
      hasher.combine(b)
    }
    Reduce(op, x, dim) => {
      hasher.combine(op)
      hasher.combine(x)
      hasher.combine(dim)
    }
    Concat(xs, dim) => {
      for x in xs {
        hasher.combine(x)
      }
      hasher.combine(dim)
    }
    Expand(x) => hasher.combine(x)
  }
}

///|
fn gcd(a : UInt, b : UInt) -> UInt {
  if b == 0 {
    return a
  }
  return gcd(b, a % b)
}

///|
fn lcm(a : UInt, b : UInt) -> UInt {
  a * b / gcd(a, b)
}

///|
fn compute_block(shape : Array[UInt]) -> Array[UInt] {
  let mut dimension = shape.length()
  let block = Array::make(dimension, 1U)
  dimension -= 1
  while dimension > 0 {
    block[dimension - 1] = block[dimension] * shape[dimension]
    dimension -= 1
  }
  block
}

///|
pub fn Tensor::broadcast[T](
  self : Tensor[T],
  other : Tensor[T]
) -> (Tensor[T], Tensor[T]) {
  let self_shape = self.shape
  let self_dim = self_shape.length()
  let other_shape = other.shape
  let other_dim = other_shape.length()
  let dim = @math.maximum(self_dim, other_dim)
  let shape = Array::make(dim, 1U)
  let self_dim_offset = dim - self_dim
  for i in 0..<self_dim {
    let shape_i = i + self_dim_offset
    shape[shape_i] = lcm(shape[shape_i], self_shape[i])
  }
  let other_dim_offset = dim - other_dim
  for i in 0..<other_dim {
    let shape_i = i + other_dim_offset
    shape[shape_i] = lcm(shape[shape_i], other_shape[i])
  }
  let self = Tensor::new(shape, Expand(self))
  let other = Tensor::new(shape, Expand(other))
  (self, other)
}

///|
pub fn Tensor::add[T](self : Tensor[T], other : Tensor[T]) -> Tensor[T] {
  let (self, other) = self.broadcast(other)
  Tensor::new(self.shape, Binary(Add, self, other))
}

///|
trait Dtype {
  compile() -> @type.Type
  into(FixedArray[Self]) -> @dtype.DtypeArray
  from(@dtype.DtypeArray) -> FixedArray[Self]
}

///|
fn Tensor::compute[T : Hash + Eq + Show + Default + Dtype](
  self : Tensor[T]
) -> Unit {
  let schedule = self.schedule()
  self.device.execute(schedule)
}

///|
fn Tensor::value[T : Hash + Eq + Show + Default + Dtype](
  self : Tensor[T]
) -> FixedArray[T] {
  self.compute()
  T::from(self.device.get(self.buffer.unwrap()))
}

///|
fn Tensor::schedule[T : Hash + Eq + Show + Default + Dtype](
  self : Tensor[T]
) -> Array[Schedule] {
  let args : Array[@type.Type] = []
  let bufs : Array[(Int, @expr.Var)] = []
  let mut tmps = 0
  let tmps_cache : Map[@expr.Expr, Int] = Map::new()
  let expr_cache : Map[(Tensor[T], @immut/array.T[@expr.Expr]), @expr.Expr] = Map::new()
  fn get_arg(ty : @type.Type) -> @expr.Var {
    let arg_id = args.length()
    args.push(ty)
    @expr.arg(arg_id)
  }

  fn get_tmp() -> Int {
    let tmp_id = tmps
    tmps += 1
    tmp_id
  }

  fn let_tmp(expr : @expr.Expr, k : (@expr.Expr) -> @expr.Expr) -> @expr.Expr {
    guard let None = tmps_cache[expr] else {
      Some(tmp_id) => k(@expr.var(@expr.tmp(tmp_id)))
    }
    let tmp_id = get_tmp()
    tmps_cache[expr] = tmp_id
    @expr.let_(tmp_id, expr, k(@expr.var(@expr.tmp(tmp_id))))
  }

  fn compute_flat_index(
    index : Array[@expr.Expr],
    shape : Array[UInt],
    block : Array[UInt]
  ) -> @expr.Expr {
    let mut flat = @expr.u32(0)
    for i in 0..<shape.length() {
      flat = flat.add(index[i].mul_u32(block[i]))
    }
    flat
  }

  fn compile(
    self : Tensor[T],
    index : Array[@expr.Expr],
    k : (@expr.Expr) -> @expr.Expr
  ) -> @expr.Expr {
    let shape = self.shape
    let block = self.block()
    let total = if shape.length() == 0 { 1U } else { shape[0] * block[0] }
    let immut_index = @immut/array.from_iter(index.iter())
    guard let None = expr_cache[(self, immut_index)] else {
      Some(expr) => k(expr)
    }
    let k = fn(expr : @expr.Expr) -> @expr.Expr {
      expr_cache[(self, immut_index)] = expr
      k(expr)
    }
    guard let None = self.buffer else {
      Some(buf) => {
        let idx = compute_flat_index(index, shape, block)
        let arg = for b in bufs {
          if b.0 == buf {
            break b.1
          }
        } else {
          let arg = get_arg(@type.arr(T::compile(), total))
          bufs.push((buf, arg))
          arg
        }
        let_tmp(idx, fn(idx) { let_tmp(@expr.get(arg, idx), k) })
      }
    }
    guard let None = self.value else {
      Some(value) => {
        println("self.value: \{self.value}")
        let idx = compute_flat_index(index, shape, block)
        let arg = get_arg(@type.arr(T::compile(), total))
        let buf = self.device.new(T::into(value))
        self.buffer = Some(buf)
        bufs.push((buf, arg))
        let_tmp(idx, fn(idx) { let_tmp(@expr.get(arg, idx), k) })
      }
    }
    match self.graph {
      Val(val) => {
        let idx = compute_flat_index(index, shape, block)
        let arg = get_arg(@type.arr(T::compile(), total))
        let buf = self.device.new(T::into(val))
        self.buffer = Some(buf)
        bufs.push((buf, arg))
        let_tmp(idx, fn(idx) { let_tmp(@expr.get(arg, idx), k) })
      }
      Binary(op, a, b) =>
        compile(a, index, fn(a_expr) {
          compile(b, index, fn(b_expr) {
            let val = match op {
              Add => a_expr.add(b_expr)
              Mul => a_expr.mul(b_expr)
            }
            let_tmp(val, k)
          })
        })
      Get(a) => {
        let mut f_index = compute_flat_index(index, shape, block)
        let a_index = []
        for b in a.block() {
          a_index.push(f_index.div_u32(b))
          f_index = f_index.mod_u32(b)
        }
        compile(a, a_index, k)
      }
      Expand(a) => {
        let a_index = []
        for i, s in a.shape {
          if self.shape[i] == s {
            a_index.push(index[i])
          } else {
            a_index.push(index[i].mod_u32(s))
          }
        }
        compile(a, a_index, k)
      }
      Reduce(op, a, dim) => {
        let sum_id = get_tmp()
        let sum_tmp = @expr.tmp(sum_id)
        let sum_var = @expr.var(sum_tmp)
        let for_idx_id = get_tmp()
        let for_idx_tmp = @expr.tmp(for_idx_id)
        let for_idx_var = @expr.var(for_idx_tmp)
        let a_index = []
        for i in 0..<dim {
          a_index.push(index[i])
        }
        a_index.push(for_idx_var)
        for i in (dim + 1)..<a.shape.length() {
          a_index.push(index[i - 1])
        }
        @expr.mut_(
          sum_id,
          @expr.u32(0),
          @expr.seq(
            @expr.for_(
              for_idx_id,
              a.shape[dim],
              compile(a, a_index, fn(a_expr) {
                let val = match op {
                  Add => sum_var.add(a_expr)
                  Mul => sum_var.add(a_expr)
                }
                @expr.set(sum_id, val)
              }),
            ),
            k(sum_var),
          ),
        )
      }
      Concat(xs, dim) => {
        let mut total = xs[0].shape[dim]
        let index = index.copy()
        let mut expr = compile(xs[0], index, k)
        for i in 1..<xs.length() {
          let x = xs[i]
          let index_dim = index[dim]
          index[dim] = index[dim].sub_u32(total)
          expr = index_dim.cmp_ge_u32(total).sel(compile(x, index, k), expr)
          total += x.shape[dim]
        }
        expr
      }
    }
  }

  let shape = self.shape
  let block = compute_block(shape)
  let total = self.shape.fold(init=1U, fn(acc, s) { acc * s })
  let index = Array::makei(self.shape.length(), fn(i) {
    @expr.var(@expr.idx(i))
  })
  let f_index = compute_flat_index(index, shape, block)
  let kernel = compile(self, index, fn(expr) {
    @expr.set_idx(@expr.out, f_index, expr)
  })
  let out_buf = self.device.new(
    @dtype.i32(FixedArray::make(total.reinterpret_as_int(), 0)),
  )
  self.buffer = Some(out_buf)
  let out_ty = @type.arr(T::compile(), total)
  let kernel = Kernel::new(args, out_ty, self.shape, kernel)
  [{ inputs: bufs.map(fn(buf) { buf.0 }), output: out_buf, kernel }]
}

///|
pub fn Tensor::reshape[T](self : Tensor[T], shape : Array[UInt]) -> Tensor[T] {
  Tensor::new(shape, Get(self))
}

///|
pub fn Tensor::mul[T](self : Tensor[T], other : Tensor[T]) -> Tensor[T] {
  let (self, other) = self.broadcast(other)
  Tensor::new(self.shape, Binary(Mul, self, other))
}

///|
pub fn Tensor::sum[T](self : Tensor[T], dim : Int) -> Tensor[T] {
  let shape = []
  for i in 0..<dim {
    shape.push(self.shape[i])
  }
  for i in (dim + 1)..<self.shape.length() {
    shape.push(self.shape[i])
  }
  Tensor::new(shape, Reduce(Add, self, dim))
}

///|
pub fn Tensor::matmul[T](self : Tensor[T], other : Tensor[T]) -> Tensor[T] {
  let self = match self.shape {
    [.. as shape, r, c] => self.reshape([..shape, 1, r, c])
    _ => abort("")
  }
  let other = other.transpose(
    other.shape.length() - 2,
    other.shape.length() - 1,
  )
  let other = match other.shape {
    [.. as shape, r, c] => other.reshape([..shape, r, 1, c])
    _ => abort("")
  }
  let dot = self.mul(other)
  dot.sum(dot.shape.length() - 1)
}

///|
pub fn Tensor::transpose[T](
  self : Tensor[T],
  dim0 : Int,
  dim1 : Int
) -> Tensor[T] {
  let shape = self.shape.copy()
  let block = self.block().copy()
  shape.swap(dim0, dim1)
  block.swap(dim0, dim1)
  Tensor::{
    shape,
    block: Some(block),
    value: None,
    graph: Get(self),
    device: self.device,
    buffer: None,
  }
}

///|
impl Dtype for Int with compile() -> @type.Type { @type.I32 }

///|
impl Dtype for Int with into(self : FixedArray[Int]) -> @dtype.DtypeArray {
  @dtype.i32(self)
}

///|
impl Dtype for Int with from(self : @dtype.DtypeArray) -> FixedArray[Int] {
  match self {
    I32(array) => array
    _ => abort("")
  }
}

test {
  let v = Tensor::new(
    [2, 2, 3],
    Val([7, 18, 33, 28, 45, 66, 8, 20, 36, 32, 50, 72]),
  )
  let s = v.sum(v.shape.length() - 1)
  inspect!(s.value(), content="[58, 139, 64, 154]")
}

test {
  let a = Tensor::new([1, 2, 3], Val([1, 2, 3, 4, 5, 6]))
  let b = Tensor::new([2, 1, 3], Val([7, 9, 11, 8, 10, 12]))
  let c = a.mul(b)
  inspect!(c.shape, content="[2, 2, 3]")
  inspect!(c.value(), content="[7, 18, 33, 28, 45, 66, 8, 20, 36, 32, 50, 72]")
}

test {
  let a = Tensor::new([1, 2, 3], Val([1, 2, 3, 4, 5, 6]))
  let b = Tensor::new([2, 1, 3], Val([7, 9, 11, 8, 10, 12]))
  let c = a.mul(b).sum(2)
  inspect!(c.shape, content="[2, 2]")
  inspect!(c.value(), content="[58, 139, 64, 154]")
}

test {
  let a = Tensor::new([2, 3], Val([1, 2, 3, 4, 5, 6]))
  let b = Tensor::new([3, 2], Val([7, 9, 11, 8, 10, 12]))
  let c = a.matmul(b)
  inspect!(c.shape, content="[2, 2]")
  inspect!(c.value(), content="[58, 139, 64, 154]")
}
