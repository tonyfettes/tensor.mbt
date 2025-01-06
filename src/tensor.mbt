///|
struct Tensor[T] {
  shape : Array[Int]
  mut block : Array[Int]?
  value : Array[T]?
  graph : Graph[T]
} derive(Show)

///|
impl[T : Hash] Hash for Tensor[T] with hash_combine(
  self : Tensor[T],
  hasher : Hasher
) {
  for s in self.shape {
    hasher.combine_int(s)
  }
  Hash::hash_combine(self.graph, hasher)
}

///|
impl[T : Eq] Eq for Tensor[T] with op_equal(self : Tensor[T], other : Tensor[T]) -> Bool {
  self.shape == other.shape && self.graph == other.graph
}

///|
fn Tensor::new[T](shape : Array[Int], graph : Graph[T]) -> Tensor[T] {
  { shape, value: None, block: None, graph }
}

///|
fn Tensor::block[T](self : Tensor[T]) -> Array[Int] {
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
fn gcd(a : Int, b : Int) -> Int {
  if b == 0 {
    return a
  }
  return gcd(b, a % b)
}

///|
fn lcm(a : Int, b : Int) -> Int {
  a * b / gcd(a, b)
}

///|
fn compute_block_size(shape : Array[Int]) -> Array[Int] {
  let mut dimension = shape.length()
  let block = Array::make(dimension, 1)
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
  let shape = Array::make(dim, 1)
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
fn compile_index(
  shape : Array[Int],
  block : Array[Int],
  k : (@expr.Expr) -> @expr.Expr
) -> @expr.Expr {
  fn compile_index_i(
    i : Int,
    acc : @expr.Expr,
    k : (@expr.Expr) -> @expr.Expr
  ) {
    if i == shape.length() {
      return k(acc)
    }
    let block_i = block[i]
    compile_index_i(i + 1, acc.add(@expr.var_idx(i).mul_i32(block_i)), k)
  }

  compile_index_i(0, @expr.i32(0), k)
}

///|
pub fn Tensor::compile[T : Hash + Eq + Dtype + Show](
  self : Tensor[T]
) -> @expr.Expr {
  let args : Array[@type.Type] = []
  let args_cache : Map[@immut/array.T[T], Int] = Map::new()
  let tmps : Ref[Int] = @ref.new(0)
  let tmps_cache : Map[@expr.Expr, Int] = Map::new()
  let ty = T::compile()
  let cache : Map[(Tensor[T], @immut/array.T[@expr.Expr]), @expr.Expr] = Map::new()
  fn get_var_arg(value : FixedArray[T]) -> @expr.Expr {
    let immut_value = @immut/array.from_iter(value.iter())
    guard let None = args_cache[immut_value] else {
      Some(arg_id) => return @expr.var_arg(arg_id)
    }
    let arg_id = args.length()
    args.push(@type.ptr_i32)
    args_cache[immut_value] = arg_id
    @expr.var_arg(arg_id)
  }

  fn get_tmp(expr : @expr.Expr) -> @expr.Var {
    guard let None = tmps_cache[expr] else {
      Some(tmp_id) => return @expr.tmp(tmp_id)
    }
    let tmp_id = tmps.val
    tmps.val += 1
    tmps_cache[expr] = tmp_id
    @expr.tmp(tmp_id)
  }

  fn compile(
    self : Tensor[T],
    index : Array[@expr.Expr],
    k : (@expr.Expr) -> @expr.Expr
  ) -> @expr.Expr {
    let immut_index = @immut/array.from_iter(index.iter())
    guard let None = cache[(self, immut_index)] else { Some(expr) => k(expr) }
    fn compute_flat_index() -> @expr.Expr {
      let shape = self.shape
      let block = self.block()
      let mut total = @expr.i32(0)
      for i in 0..<shape.length() {
        total = total.add(index[i].mul_i32(block[i]))
      }
      total
    }

    let k = fn(expr : @expr.Expr) {
      cache[(self, immut_index)] = expr
      k(expr)
    }
    match self.graph {
      Val(value) => {
        let flat_index = compute_flat_index()
        let var_arg = get_var_arg(value)
        let tmp_idx = get_tmp(flat_index)
        let get_expr = var_arg.get(@expr.var(tmp_idx))
        let tmp_get = get_tmp(get_expr)
        @expr.let_(
          tmp_idx,
          @type.i32,
          flat_index,
          @expr.let_(tmp_get, ty, get_expr, k(@expr.var(tmp_get))),
        )
      }
      Binary(op, a, b) =>
        compile(a, index, fn(a) {
          compile(b, index, fn(b) {
            let tmp_val = match op {
              Add => a.add(b)
              Mul => a.mul(b)
            }
            let tmp = get_tmp(tmp_val)
            @expr.let_(tmp, ty, tmp_val, k(@expr.var(tmp)))
          })
        })
      Get(a) => {
        let flat_index = compute_flat_index()
        let mut flat_index = flat_index
        let a_index = []
        for b in a.block() {
          a_index.push(flat_index.div_i32(b))
          flat_index = flat_index.mod_i32(b)
        }
        compile(a, a_index, k)
      }
      Broadcast(a) => {
        let a_index = []
        for i, s in a.shape {
          if self.shape[i] == s {
            a_index.push(index[i])
          } else {
            a_index.push(index[i].mod_i32(s))
          }
        }
        compile(a, a_index, k)
      }
      Reduce(op, a, dim) => {
        let a_index = []
        for i in 0..<dim {
          a_index.push(index[i])
        }
        a_index.push(@expr.i32(0))
        for i in (dim + 1)..<a.shape.length() {
          a_index.push(index[i - 1])
        }
        fn compile_i(
          acc : @expr.Expr,
          i : Int,
          k : (@expr.Expr) -> @expr.Expr
        ) {
          if i == a.shape[dim] {
            return k(acc)
          }
          a_index[dim] = @expr.i32(i)
          compile(a, a_index, fn(expr) {
            let tmp_val = match op {
              Add => acc.add(expr)
              Mul => acc.mul(expr)
            }
            let tmp = get_tmp(tmp_val)
            @expr.let_(tmp, ty, tmp_val, compile_i(@expr.var(tmp), i + 1, k))
          })
        }

        compile(a, a_index, fn(expr) { compile_i(expr, 1, k) })
      }
      Concat(xs, dim) => {
        let mut total = xs[0].shape[dim]
        let index = index.copy()
        let mut expr = compile(xs[0], index, k)
        for i in 1..<xs.length() {
          let x = xs[i]
          let index_dim = index[dim]
          index[dim] = index[dim].sub_i32(total)
          expr = index_dim.if_ge(@expr.i32(total), compile(x, index, k), expr)
          total += x.shape[dim]
        }
        expr
      }
    }
  }

  let index = Array::makei(self.shape.length(), fn(i) { @expr.var_idx(i) })
  compile(self, index, fn(expr) { expr })
}

///|
pub fn Tensor::reshape[T](self : Tensor[T], shape : Array[Int]) -> Tensor[T] {
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
  let other = match other.shape {
    [.. as shape, r, c] => other.reshape([..shape, r, 1, c])
    _ => abort("")
  }
  let (self, other) = broadcast(self, other)
  let dot = self.mul(other)
  dot.sum(dot.shape.length() - 1)
}

///|
impl Dtype for Int with compile() -> @type.Type { @type.i32 }

test {
  let a = Tensor::new([2, 3], Val([1, 2, 3, 4, 5, 6]))
  let b = Tensor::new([3, 2], Val([7, 8, 9, 10, 11, 12]))
  inspect!(
    a.matmul(b).compile(),
    content=
      #|let tmp_0 : i32 = idx_1 * 3 in
      #|let tmp_1 : i32 = arg_0[tmp_0] in
      #|let tmp_2 : i32 = idx_0 * 2 in
      #|let tmp_3 : i32 = arg_1[tmp_2] in
      #|let tmp_4 : i32 = tmp_1 * tmp_3 in
      #|let tmp_5 : i32 = idx_1 * 3 + 1 in
      #|let tmp_6 : i32 = arg_0[tmp_5] in
      #|let tmp_7 : i32 = idx_0 * 2 + 1 in
      #|let tmp_8 : i32 = arg_1[tmp_7] in
      #|let tmp_9 : i32 = tmp_6 * tmp_8 in
      #|let tmp_10 : i32 = tmp_4 + tmp_9 in
      #|let tmp_11 : i32 = idx_1 * 3 + 2 in
      #|let tmp_12 : i32 = arg_0[tmp_11] in
      #|let tmp_13 : i32 = tmp_12 * tmp_3 in
      #|let tmp_14 : i32 = tmp_10 + tmp_13 in
      #|let tmp_15 : i32 = tmp_1 * tmp_8 in
      #|let tmp_16 : i32 = tmp_14 + tmp_15 in
      #|let tmp_17 : i32 = tmp_6 * tmp_3 in
      #|let tmp_18 : i32 = tmp_16 + tmp_17 in
      #|let tmp_19 : i32 = tmp_12 * tmp_8 in
      #|let tmp_20 : i32 = tmp_18 + tmp_19 in
      #|tmp_20
    ,
  )
}
