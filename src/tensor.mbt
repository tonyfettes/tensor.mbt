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
pub fn Tensor::compile[T : Hash + Eq + Dtype + Show](
  self : Tensor[T]
) -> @expr.Expr {
  let args : Array[@type.Type] = []
  let vals : Array[FixedArray[T]] = []
  let tmps : Ref[Int] = @ref.new(0)
  let ty = T::compile()
  let cache : Map[Tensor[T], @expr.Expr] = Map::new()
  fn fresh_var_arg(value : FixedArray[T]) -> @expr.Expr {
    let arg_id = args.length()
    args.push(@type.ptr_i32)
    vals.push(value)
    @expr.var_arg(arg_id)
  }

  fn fresh_tmp() -> @expr.Var {
    let tmp_id = tmps.val
    tmps.val += 1
    @expr.tmp(tmp_id)
  }

  fn id(expr : @expr.Expr) -> @expr.Expr {
    expr
  }

  fn compile(
    self : Tensor[T],
    index : Array[@expr.Expr],
    kontinue : (@expr.Expr) -> @expr.Expr
  ) -> @expr.Expr {
    println("compiling: \{self}")
    guard let None = cache[self] else { Some(expr) => kontinue(expr) }
    fn compute_flat_index() -> @expr.Expr {
      let shape = self.shape
      let block = self.block()
      let mut total = @expr.i32(0)
      for i in 0..<shape.length() {
        total = total.add(index[i].mul_i32(block[i]))
      }
      total
    }

    let kontinue = fn(expr : @expr.Expr) {
      cache[self] = expr
      kontinue(expr)
    }
    match self.graph {
      Val(value) => {
        let total = compute_flat_index()
        let var_arg = fresh_var_arg(value)
        let tmp = fresh_tmp()
        let var_tmp = @expr.var(tmp)
        @expr.let_(tmp, ty, var_arg.get(total), kontinue(var_tmp))
      }
      Binary(op, a, b) =>
        compile(a, index, fn(a) {
          compile(b, index, fn(b) {
            let tmp = fresh_tmp()
            let tmp_val = match op {
              Add => a.add(b)
              Mul => a.mul(b)
            }
            @expr.let_(tmp, ty, tmp_val, kontinue(@expr.var(tmp)))
          })
        })
      Get(a) => {
        let mut total = compute_flat_index()
        let a_index = []
        for b in a.block() {
          a_index.push(total.div_i32(b))
          total = total.mod_i32(b)
        }
        compile(a, a_index, kontinue)
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
        compile(a, a_index, kontinue)
      }
      Reduce(op, a, dim) => {
        let tmp = fresh_tmp()
        let a_index = []
        for i in 0..<dim {
          a_index.push(index[i])
        }
        a_index.push(@expr.var(tmp))
        for i in (dim + 1)..<a.shape.length() {
          a_index.push(index[i - 1])
        }
        let a_expr = compile(a, a_index, kontinue)
        let mut expr = @expr.let_(tmp, @type.i32, @expr.i32(0), a_expr)
        for i in 1..<a.shape[dim] {
          let expr_i = @expr.let_(tmp, @type.i32, @expr.i32(i), a_expr)
          match op {
            Add => expr = expr.add(expr_i)
            Mul => expr = expr.mul(expr_i)
          }
        }
        expr
      }
      Concat(xs, dim) => {
        let mut total = xs[0].shape[dim]
        let mut expr = compile(xs[0], index, kontinue)
        for i in 1..<xs.length() {
          let x = xs[i]
          let index_dim = index[dim]
          index[dim] = index[dim].sub_i32(total)
          expr = index_dim.if_ge(
            @expr.i32(total),
            compile(x, index, kontinue),
            expr,
          )
          total += x.shape[dim]
        }
        expr
      }
    }
  }

  let index = Array::makei(self.shape.length(), fn(i) { @expr.var_idx(i) })
  compile(self, index, id)
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
  let b = Tensor::new([2, 3], Val([7, 8, 9, 10, 11, 12]))
  @json.inspect!(a.matmul(b).compile(), content={
    "add": [
      {
        "add": [
          {
            "let": {
              "var": "tmp_0",
              "ty": "i32",
              "expr": 0,
              "body": {
                "let": {
                  "var": "tmp_1",
                  "ty": "i32",
                  "expr": {
                    "get": [
                      "arg_0",
                      { "add": [{ "mul": ["idx_1", 3] }, "tmp_0"] },
                    ],
                  },
                  "body": {
                    "let": {
                      "var": "tmp_2",
                      "ty": "i32",
                      "expr": {
                        "get": [
                          "arg_1",
                          { "add": [{ "mul": ["idx_0", 3] }, "tmp_0"] },
                        ],
                      },
                      "body": {
                        "let": {
                          "var": "tmp_3",
                          "ty": "i32",
                          "expr": { "mul": ["tmp_1", "tmp_2"] },
                          "body": "tmp_3",
                        },
                      },
                    },
                  },
                },
              },
            },
          },
          {
            "let": {
              "var": "tmp_0",
              "ty": "i32",
              "expr": 1,
              "body": {
                "let": {
                  "var": "tmp_1",
                  "ty": "i32",
                  "expr": {
                    "get": [
                      "arg_0",
                      { "add": [{ "mul": ["idx_1", 3] }, "tmp_0"] },
                    ],
                  },
                  "body": {
                    "let": {
                      "var": "tmp_2",
                      "ty": "i32",
                      "expr": {
                        "get": [
                          "arg_1",
                          { "add": [{ "mul": ["idx_0", 3] }, "tmp_0"] },
                        ],
                      },
                      "body": {
                        "let": {
                          "var": "tmp_3",
                          "ty": "i32",
                          "expr": { "mul": ["tmp_1", "tmp_2"] },
                          "body": "tmp_3",
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        ],
      },
      {
        "let": {
          "var": "tmp_0",
          "ty": "i32",
          "expr": 2,
          "body": {
            "let": {
              "var": "tmp_1",
              "ty": "i32",
              "expr": {
                "get": ["arg_0", { "add": [{ "mul": ["idx_1", 3] }, "tmp_0"] }],
              },
              "body": {
                "let": {
                  "var": "tmp_2",
                  "ty": "i32",
                  "expr": {
                    "get": [
                      "arg_1",
                      { "add": [{ "mul": ["idx_0", 3] }, "tmp_0"] },
                    ],
                  },
                  "body": {
                    "let": {
                      "var": "tmp_3",
                      "ty": "i32",
                      "expr": { "mul": ["tmp_1", "tmp_2"] },
                      "body": "tmp_3",
                    },
                  },
                },
              },
            },
          },
        },
      },
    ],
  })
}
