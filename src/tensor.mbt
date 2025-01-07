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
pub fn Tensor::compile[T : Hash + Eq + Show + Default](
  self : Tensor[T]
) -> @expr.Expr {
  let args : Array[@type.Type] = []
  let args_cache : Map[@immut/array.T[T], Int] = Map::new()
  let mut tmps = 0
  let tmps_cache : Map[@expr.Expr, Int] = Map::new()
  let cache : Map[(Tensor[T], @immut/array.T[@expr.Expr]), @expr.Expr] = Map::new()
  fn get_arg(value : FixedArray[T]) -> @expr.Var {
    let immut_value = @immut/array.from_iter(value.iter())
    guard let None = args_cache[immut_value] else {
      Some(arg_id) => return @expr.arg(arg_id)
    }
    let arg_id = args.length()
    args.push(@type.i32)
    args_cache[immut_value] = arg_id
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
    k(@expr.var(@expr.tmp(tmp_id)))
  }

  fn compute_flat_index(
    self : Tensor[T],
    index : Array[@expr.Expr]
  ) -> @expr.Expr {
    let shape = self.shape
    let block = self.block()
    let mut total = @expr.i32(0)
    for i in 0..<shape.length() {
      total = total.add(index[i].mul_i32(block[i]))
    }
    total
  }

  fn id(expr : @expr.Expr) -> @expr.Expr {
    expr
  }

  fn compile(
    self : Tensor[T],
    index : Array[@expr.Expr],
    k : (@expr.Expr) -> @expr.Expr
  ) -> @expr.Expr {
    let immut_index = @immut/array.from_iter(index.iter())
    guard let None = cache[(self, immut_index)] else { Some(expr) => expr }
    match self.graph {
      Val(value) => {
        let flat_index = compute_flat_index(self, index)
        let arg = get_arg(value)
        k(@expr.get(arg, flat_index))
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
          a_index.push(f_index.div_i32(b))
          f_index = f_index.mod_i32(b)
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
        let mut expr = compile(a, a_index, id)
        for i in 1..<a.shape[dim] {
          a_index[dim] = @expr.i32(i)
          let a_expr = compile(a, a_index, id)
          expr = match op {
            Add => expr.add(a_expr)
            Mul => expr.mul(a_expr)
          }
        }
        k(expr)
      }
      Concat(xs, dim) => {
        let mut total = xs[0].shape[dim]
        let index = index.copy()
        let mut expr = compile(xs[0], index, k)
        for i in 1..<xs.length() {
          let x = xs[i]
          let index_dim = index[dim]
          index[dim] = index[dim].sub_i32(total)
          expr = index_dim.cmp_ge_i32(total).sel(compile(x, index, k), expr)
          total += x.shape[dim]
        }
        expr
      }
    }
  }

  let index = Array::makei(self.shape.length(), fn(i) {
    @expr.var(@expr.idx(i))
  })
  let block = self.block()
  let total = if self.shape.length() == 0 {
    1
  } else {
    self.shape[0] * block[0]
  }
  compile(self, index, fn(expr) {
    let f_index = compute_flat_index(self, index)
    let arg = get_arg(FixedArray::make(total, T::default()))
    @expr.set(arg, f_index, expr)
  })
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

test {
  let a = Tensor::new([2, 3], Val([1, 2, 3, 4, 5, 6]))
  let b = Tensor::new([3, 2], Val([7, 8, 9, 10, 11, 12]))
  let c = a.add(b)
  @json.inspect!(c.shape, content=[6, 6])
  @json.inspect!(a.matmul(b).compile(), content={
    "set": [
      "arg_2",
      { "add": [{ "mul": ["idx_0", 2] }, "idx_1"] },
      {
        "add": [
          {
            "add": [
              {
                "add": [
                  { "add": [{ "add": ["tmp_0", "tmp_1"] }, "tmp_2"] },
                  "tmp_3",
                ],
              },
              "tmp_4",
            ],
          },
          "tmp_5",
        ],
      },
    ],
  })
}
