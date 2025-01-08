///|
trait Device: Show {
  new(Self, @dtype.DtypeArray) -> Int
  get(Self, Int) -> @dtype.DtypeArray
  execute(Self, Array[Schedule]) -> Unit
}

///|
struct Schedule {
  inputs : Array[Int]
  output : Int
  kernel : Kernel
}

///|
impl Show for Schedule with output(self : Schedule, logger : &Logger) -> Unit {
  for i, input in self.inputs {
    logger.write_string("src[\{i}]: ")
    input.output(logger)
    logger.write_char('\n')
  }
  logger.write_string("dst: ")
  self.output.output(logger)
  logger.write_char('\n')
  self.kernel.output(logger)
}

///|
struct CPU {
  mut id : Int
  buffer : Map[Int, @dtype.DtypeArray]
} derive(Show)

///|
impl Device for CPU with new(self : CPU, value : @dtype.DtypeArray) -> Int {
  let id = self.id
  self.id += 1
  self.buffer[id] = value
  id
}

///|
impl Device for CPU with get(self : CPU, id : Int) -> @dtype.DtypeArray {
  self.buffer[id].unwrap()
}

///|
impl Device for CPU with execute(self : CPU, schedule : Array[Schedule]) -> Unit {
  enum Value {
    Unit
    Bool(Bool)
    Int(Int)
    Array(@dtype.DtypeArray)
  } derive(Show)
  for s in schedule {
    let kernel = s.kernel
    let inputs = s.inputs
    let output = s.output
    let shape = kernel.shape()
    let environment = Map::new()
    fn interpret(expr : @expr.Expr, index : Array[Int]) -> Value {
      fn get_var(var : @expr.Var) -> Value {
        match var {
          Tmp(var) => environment[var].unwrap()
          Idx(idx) => Int(index[idx])
          Arg(id) => Array(self.get(inputs[id]))
          Out => Array(self.get(output))
        }
      }

      fn get_idx(value : Value, index : Value) -> Value {
        match (value, index) {
          (Array(I32(array)), Int(index)) => Int(array[index])
          _ => abort("")
        }
      }

      fn set_idx(array : Value, index : Value, value : Value) -> Unit {
        match (array, index, value) {
          (Array(I32(array)), Int(index), Int(value)) => array[index] = value
          _ => abort("")
        }
      }

      let r = match expr {
        Bin(bool) => Bool(bool)
        U32(u32) => Int(u32.reinterpret_as_int())
        Var(var) => get_var(var)
        Get(var, idx) => {
          let idx = interpret(idx, index)
          get_idx(get_var(var), idx)
        }
        Set(Get(var, idx), value) => {
          let idx = interpret(idx, index)
          let value = interpret(value, index)
          let array = get_var(var)
          set_idx(array, idx, value)
          Unit
        }
        Add(a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Int(a + b)
            _ => abort("")
          }
        }
        Sub(a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Int(a - b)
            _ => abort("")
          }
        }
        Mul(a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Int(a * b)
            _ => abort("")
          }
        }
        Mod(a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Int(a % b)
            _ => abort("")
          }
        }
        Div(a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Int(a / b)
            _ => abort("")
          }
        }
        Cmp(Lt, a, b) => {
          let a = interpret(a, index)
          let b = interpret(b, index)
          match (a, b) {
            (Int(a), Int(b)) => Bool(a < b)
            _ => abort("")
          }
        }
        Not(expr) => {
          guard let Bool(bool) = interpret(expr, index)
          Bool(not(bool))
        }
        Sel(cond, a, b) => {
          guard let Bool(cond) = interpret(cond, index)
          if cond {
            interpret(a, index)
          } else {
            interpret(b, index)
          }
        }
        Let(var, expr, body) | Mut(var, expr, body) => {
          let value = interpret(expr, index)
          environment[var] = value
          interpret(body, index)
        }
        Set(Var(var), value) => {
          let value = interpret(value, index)
          environment[var] = value
          Unit
        }
        For(var, end, body) => {
          for i in 0..<end.reinterpret_as_int() {
            environment[var] = Int(i)
            guard let Unit = interpret(body, index)

          }
          Unit
        }
        Seq(a, b) => {
          guard let Unit = interpret(a, index)
          guard let Unit = interpret(b, index)
          Unit
        }
      }
      r
    }

    fn schedule(dim : Int, index : Array[Int]) -> Unit {
      if dim < shape.length() {
        for i in 0..<shape[dim] {
          schedule(dim + 1, [..index, i])
        }
        return
      } else {
        interpret(kernel.value, index) |> ignore
      }
    }

    schedule(0, [])
  }
}

///|
let cpu : CPU = CPU::{ id: 0, buffer: Map::new() }
