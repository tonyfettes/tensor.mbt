///|
struct Tensor[T] {
  shape : Array[UInt]
  mut block : Array[UInt]?
  graph : Graph[T]
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
fn Tensor::new[T](shape : Array[UInt], graph : Graph[T]) -> Tensor[T] {
  { shape, block: None, graph }
}

///|
fn Tensor::block[T](self : Tensor[T]) -> Array[UInt] {
  guard let None = self.block else { Some(block) => block }
  let block = compute_block_size(self.shape)
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
  Broadcast(Tensor[T])
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
    Broadcast(_) => 5
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
    Broadcast(x) => hasher.combine(x)
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
fn compute_block_size(shape : Array[UInt]) -> Array[UInt] {
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
  let self = Tensor::new(shape, Broadcast(self))
  let other = Tensor::new(shape, Broadcast(other))
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
}

///|
fn Tensor::compile[T : Hash + Eq + Show + Default + Dtype](
  self : Tensor[T]
) -> @kernel.Kernel {
  let args : Array[@type.Type] = []
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
    self : Tensor[T],
    index : Array[@expr.Expr]
  ) -> @expr.Expr {
    let shape = self.shape
    let block = self.block()
    let mut total = @expr.u32(0)
    for i in 0..<shape.length() {
      total = total.add(index[i].mul_u32(block[i]))
    }
    total
  }

  fn compile(
    self : Tensor[T],
    index : Array[@expr.Expr],
    k : (@expr.Expr) -> @expr.Expr
  ) -> @expr.Expr {
    let immut_index = @immut/array.from_iter(index.iter())
    guard let None = expr_cache[(self, immut_index)] else {
      Some(expr) => k(expr)
    }
    let k = fn(expr : @expr.Expr) -> @expr.Expr {
      expr_cache[(self, immut_index)] = expr
      k(expr)
    }
    match self.graph {
      Val(val) => {
        let idx = compute_flat_index(self, index)
        let arg = get_arg(T::compile())
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
        let mut f_index = compute_flat_index(self, index)
        let a_index = []
        for b in a.block() {
          a_index.push(f_index.div_u32(b))
          f_index = f_index.mod_u32(b)
        }
        compile(a, a_index, k)
      }
      Broadcast(a) => {
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
                sum_tmp.set(val)
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

  let index = Array::makei(self.shape.length(), fn(i) {
    @expr.var(@expr.idx(i))
  })
  let f_index = compute_flat_index(self, index)
  let arg = get_arg(T::compile())
  let kernel = compile(self, index, fn(expr) {
    @expr.set_idx(arg, f_index, expr)
  })
  let kernel = @kernel.Kernel::new(args, kernel)
  kernel
}

///|
pub fn Tensor::reshape[T](self : Tensor[T], shape : Array[UInt]) -> Tensor[T] {
  Tensor::new(shape, Get(self))
}

///|
pub fn Tensor::mul[T](self : Tensor[T], other : Tensor[T]) -> Tensor[T] {
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
  let (self, other) = broadcast(self, other)
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
  Tensor::{ shape, block: Some(block), graph: Get(self) }
}

///|
impl Dtype for Int with compile() -> @type.Type { @type.I32 }

test {
  let a = Tensor::new([2, 3], Val([1]))
  let b = Tensor::new([3, 2], Val([7]))
  let c = a.matmul(b)
  inspect!(
    @wgsl.ToWgsl::to_wgsl(c.compile()),
    content=
      #|@group(0) @binding(1)
      #|var<storage, read_write> arg1: array<i32>;
      #|@group(0) @binding(2)
      #|var<storage, read_write> arg2: array<i32>;
      #|@group(0) @binding(3)
      #|var<storage, read_write> arg3: array<i32>;
      #|@compute
      #|fn main(
      #|  @builtin(global_invocation_id)
      #|  global_id : vec3u,
      #|) {
      #|  let idx0 = global_id.x;
      #|  var tmp0 = u32(0); for (var tmp1 = u32(0); tmp1 < 3; tmp1++) { let tmp2 = idx1 * u32(3) + tmp1; let tmp3 = arg1[tmp2]; let tmp4 = idx0 * u32(3) + tmp1; let tmp5 = arg2[tmp4]; let tmp6 = tmp3 * tmp5; tmp0 = tmp0 + tmp6; }; arg0[idx0 * u32(2) + idx1] = tmp0;
      #|}
    ,
  )
}
