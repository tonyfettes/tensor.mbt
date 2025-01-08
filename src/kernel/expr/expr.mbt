///|
pub enum Var {
  Arg(Int)
  Tmp(Int)
  Idx(Int)
  Out
} derive(Eq, Hash)

///|
pub fn Var::arg(id : Int) -> Var {
  Arg(id)
}

///|
pub fn Var::tmp(id : Int) -> Var {
  Tmp(id)
}

///|
pub fn Var::idx(id : Int) -> Var {
  Idx(id)
}

pub let out : Var = Out

///|
pub impl Show for Var with output(self : Var, logger : &Logger) -> Unit {
  match self {
    Arg(id) => logger.write_string("arg\{id}")
    Tmp(id) => logger.write_string("tmp\{id}")
    Idx(id) => logger.write_string("idx\{id}")
    Out => logger.write_string("out")
  }
}

///|
impl ToJson for Var with to_json(self : Var) -> Json {
  Json::String(self.to_string())
}

///|
pub enum Cmp {
  Lt
} derive(Eq, ToJson, Hash)

///|
pub enum Left {
  Get(Var, Expr)
  Var(Int)
} derive(Eq, Hash)

///|
pub enum Expr {
  Bin(Bool)
  U32(UInt)
  Var(Var)
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Mod(Expr, Expr)
  Div(Expr, Expr)
  Get(Var, Expr)
  Set(Left, Expr)
  Cmp(Cmp, Expr, Expr)
  Not(Expr)
  Sel(Expr, Expr, Expr)
  Let(Int, Expr, Expr)
  Mut(Int, Expr, Expr)
  For(Int, UInt, Expr)
  Seq(Expr, Expr)
} derive(Eq, Hash)

///|
pub fn Expr::bin(bool : Bool) -> Expr {
  Bin(bool)
}

///|
pub fn Expr::u32(u32 : UInt) -> Expr {
  U32(u32)
}

///|
pub fn Expr::var(var : Var) -> Expr {
  Var(var)
}

///|
pub fn Var::get(self : Var, index : Expr) -> Expr {
  Get(self, index)
}

///|
pub fn Var::set_idx(self : Var, index : Expr, value : Expr) -> Expr {
  Set(Get(self, index), value)
}

///|
pub fn Var::set(self : Int, value : Expr) -> Expr {
  Set(Var(self), value)
}

///|
pub fn Expr::add(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (U32(self), U32(other)) => U32(self + other)
    (U32(0), other) => other
    (self, U32(0)) => self
    (Sub(a, b), c) => if b == c { a } else { Add(Sub(a, b), c) }
    (self, other) => Add(self, other)
  }
}

///|
pub fn Expr::add_u32(self : Expr, u32 : UInt) -> Expr {
  self.add(U32(u32))
}

///|
pub fn Expr::sub(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (U32(self), U32(other)) => U32(self + other)
    (self, U32(0)) => self
    (self, other) => if self == other { U32(0) } else { Sub(self, other) }
  }
}

///|
pub fn Expr::sub_u32(self : Expr, u32 : UInt) -> Expr {
  self.sub(U32(u32))
}

///|
pub fn Expr::mul(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (U32(self), U32(other)) => U32(self * other)
    (U32(0), _) | (_, U32(0)) => U32(0)
    (U32(1), other) => other
    (self, U32(1)) => self
    (Div(self, self_div), other) =>
      if self_div == other {
        self.sub(self.mod(self_div))
      } else {
        Mul(Div(self, self_div), other)
      }
    (self, other) => Mul(self, other)
  }
}

///|
pub fn Expr::mul_u32(self : Expr, u32 : UInt) -> Expr {
  self.mul(U32(u32))
}

///|
pub fn Expr::div(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (_, U32(0)) => abort("Division by zero")
    (U32(self), U32(other)) => U32(self / other)
    (self, U32(1)) => self
    (Mul(a, b), c) => if b == c { a } else { Div(Mul(a, b), c) }
    (self, other) => Div(self, other)
  }
}

///|
pub fn Expr::div_u32(self : Expr, u32 : UInt) -> Expr {
  self.div(U32(u32))
}

///|
pub fn Expr::mod(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (_, U32(0)) => abort("Division by zero")
    (U32(self), U32(other)) => U32(self % other)
    (_, U32(1)) => U32(0)
    (Mul(a, b), c) => if b == c { U32(0) } else { Mod(Mul(a, b), c) }
    (self, other) => Mod(self, other)
  }
}

///|
pub fn Expr::mod_u32(self : Expr, u32 : UInt) -> Expr {
  self.mod(U32(u32))
}

///|
pub fn Expr::cmp_lt(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (U32(self), U32(other)) => Bin(self < other)
    (self, other) => Cmp(Lt, self, other)
  }
}

///|
pub fn Expr::cmp_ge(self : Expr, other : Expr) -> Expr {
  self.cmp_lt(other).not()
}

///|
pub fn Expr::cmp_ge_u32(self : Expr, u32 : UInt) -> Expr {
  self.cmp_ge(U32(u32))
}

///|
pub fn Expr::not(self : Expr) -> Expr {
  match self {
    Bin(self) => Bin(not(self))
    self => Not(self)
  }
}

///|
pub fn Expr::let_(var : Int, value : Expr, body : Expr) -> Expr {
  Let(var, value, body)
}

///|
pub fn Expr::mut_(var : Int, value : Expr, body : Expr) -> Expr {
  Mut(var, value, body)
}

///|
pub fn Expr::sel(self : Expr, if_true : Expr, if_false : Expr) -> Expr {
  match self {
    Bin(true) => if_true
    Bin(false) => if_false
    self => Sel(self, if_true, if_false)
  }
}

///|
pub fn Expr::for_(self : Int, length : UInt, body : Expr) -> Expr {
  For(self, length, body)
}

///|
pub fn Expr::seq(self : Expr, other : Expr) -> Expr {
  Seq(self, other)
}

///|
pub impl Show for Expr with output(self : Expr, logger : &Logger) -> Unit {
  fn output(self : Expr, logger : &Logger, level : Int) -> Unit {
    fn write_newline(logger : &Logger, level : Int) -> Unit {
      logger.write_string("\n")
      for _ in 0..<level {
        logger.write_string("  ")
      }
    }

    match self {
      Bin(true) => logger.write_string("true")
      Bin(false) => logger.write_string("false")
      U32(int) => logger.write_string(int.to_string())
      Var(var) => var.output(logger)
      Add(a, b) => logger.write_string("\{a} + \{b}")
      Sub(a, b) => logger.write_string("\{a} - \{b}")
      Mul(a, b) => logger.write_string("\{a} * \{b}")
      Div(a, b) => logger.write_string("\{a} / \{b}")
      Mod(a, b) => logger.write_string("\{a} % \{b}")
      Get(x, i) => logger.write_string("\{x}[\{i}]")
      Set(Get(x, i), v) => logger.write_string("\{x}[\{i}] = \{v}")
      Set(Var(x), v) => logger.write_string("tmp\{x} = \{v}")
      Cmp(Lt, a, b) => logger.write_string("\{a} < \{b}")
      Not(a) => logger.write_string("!\{a}")
      Sel(cond, if_true, if_false) => {
        logger.write_string("if \{cond} {")
        write_newline(logger, level + 1)
        output(if_true, logger, level + 1)
        write_newline(logger, level)
        logger.write_string("} else {")
        write_newline(logger, level + 1)
        output(if_false, logger, level + 1)
        write_newline(logger, level)
        logger.write_string("}")
      }
      Let(var, expr, body) => {
        logger.write_string("let tmp\{var} = \{expr} in")
        write_newline(logger, level)
        output(body, logger, level)
      }
      Mut(var, expr, body) => {
        logger.write_string("var tmp\{var} = \{expr} in")
        write_newline(logger, level)
        output(body, logger, level)
      }
      Seq(a, b) => {
        output(a, logger, level)
        write_newline(logger, level)
        output(b, logger, level)
      }
      For(var, len, expr) => {
        logger.write_string("for tmp\{var} in 0..\{len} {")
        write_newline(logger, level + 1)
        output(expr, logger, level + 1)
        write_newline(logger, level)
        logger.write_string("}")
      }
    }
  }

  output(self, logger, 0)
}

///|
pub impl ToJson for Expr with to_json(self : Expr) -> Json {
  match self {
    Bin(true) => Json::True
    Bin(false) => Json::False
    U32(u32) => Json::Number(u32.to_float().to_double())
    Var(var) => var.to_string().to_json()
    Add(a, b) => { "add": [a.to_json(), b.to_json()] }
    Sub(a, b) => { "sub": [a.to_json(), b.to_json()] }
    Mul(a, b) => { "mul": [a.to_json(), b.to_json()] }
    Div(a, b) => { "div": [a.to_json(), b.to_json()] }
    Mod(a, b) => { "mod": [a.to_json(), b.to_json()] }
    Get(a, b) => { "get": [a.to_json(), b.to_json()] }
    Set(Get(x, i), v) => { "set": [x.to_json(), i.to_json(), v.to_json()] }
    Set(Var(x), v) => { "set": [x.to_json(), v.to_json()] }
    Cmp(Lt, a, b) => { "cmp": { "lt": [a.to_json(), b.to_json()] } }
    Not(a) => { "not": a.to_json() }
    Sel(cond, if_true, if_false) =>
      {
        "if": {
          "cond": cond.to_json(),
          "then": if_true.to_json(),
          "else": if_false.to_json(),
        },
      }
    Let(var, expr, body) =>
      {
        "let": {
          "var": var.to_json(),
          "expr": expr.to_json(),
          "body": body.to_json(),
        },
      }
    For(var, length, body) =>
      {
        "for": {
          "var": var.to_json(),
          "length": length.to_float().to_json(),
          "body": body.to_json(),
        },
      }
    Mut(var, expr, body) =>
      {
        "mut": {
          "var": var.to_json(),
          "expr": expr.to_json(),
          "body": body.to_json(),
        },
      }
    Seq(a, b) => [a.to_json(), b.to_json()]
  }
}
