///|
enum Var {
  Arg(Int)
  Tmp(Int)
  Idx(Int)
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

///|
impl Show for Var with output(self : Var, logger : &Logger) -> Unit {
  match self {
    Arg(id) => logger.write_string("arg_\{id}")
    Tmp(id) => logger.write_string("tmp_\{id}")
    Idx(id) => logger.write_string("idx_\{id}")
  }
}

///|
impl ToJson for Var with to_json(self : Var) -> Json {
  Json::String(self.to_string())
}

///|
priv enum Cmp {
  Lt
} derive(Eq, ToJson, Hash)

///|
enum Expr {
  Bin(Bool)
  I32(Int)
  Var(Var)
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Mod(Expr, Expr)
  Div(Expr, Expr)
  Get(Var, Expr)
  Set(Var, Expr, Expr)
  Cmp(Cmp, Expr, Expr)
  Not(Expr)
  Sel(Expr, Expr, Expr)
  Let(Int, Expr, Expr)
  Mut(Int, Expr)
  For(Int, Int, Expr)
  Seq(Expr, Expr)
} derive(Eq, Hash)

///|
pub fn Expr::bin(bool : Bool) -> Expr {
  Bin(bool)
}

///|
pub fn Expr::i32(int : Int) -> Expr {
  I32(int)
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
pub fn Var::set(self : Var, index : Expr, value : Expr) -> Expr {
  Set(self, index, value)
}

///|
pub fn Expr::add(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (I32(self), I32(other)) => I32(self + other)
    (I32(0), other) => other
    (self, I32(0)) => self
    (Sub(a, b), c) => if b == c { a } else { Add(Sub(a, b), c) }
    (self, other) => Add(self, other)
  }
}

///|
pub fn Expr::add_i32(self : Expr, int : Int) -> Expr {
  self.add(I32(int))
}

///|
pub fn Expr::sub(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (I32(self), I32(other)) => I32(self + other)
    (self, I32(0)) => self
    (self, other) => if self == other { I32(0) } else { Sub(self, other) }
  }
}

///|
pub fn Expr::sub_i32(self : Expr, int : Int) -> Expr {
  self.sub(I32(int))
}

///|
pub fn Expr::mul(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (I32(self), I32(other)) => I32(self * other)
    (I32(0), _) | (_, I32(0)) => I32(0)
    (I32(1), other) => other
    (self, I32(1)) => self
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
pub fn Expr::mul_i32(self : Expr, int : Int) -> Expr {
  self.mul(I32(int))
}

///|
pub fn Expr::div(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (_, I32(0)) => abort("Division by zero")
    (I32(self), I32(other)) => I32(self / other)
    (self, I32(1)) => self
    (Mul(a, b), c) => if b == c { a } else { Div(Mul(a, b), c) }
    (self, other) => Div(self, other)
  }
}

///|
pub fn Expr::div_i32(self : Expr, int : Int) -> Expr {
  self.div(I32(int))
}

///|
pub fn Expr::mod(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (_, I32(0)) => abort("Division by zero")
    (I32(self), I32(other)) => I32(self % other)
    (_, I32(1)) => I32(0)
    (Mul(a, b), c) => if b == c { I32(0) } else { Mod(Mul(a, b), c) }
    (self, other) => Mod(self, other)
  }
}

///|
pub fn Expr::mod_i32(self : Expr, int : Int) -> Expr {
  self.mod(I32(int))
}

///|
pub fn Expr::cmp_lt(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (I32(self), I32(other)) => Bin(self < other)
    (self, other) => Cmp(Lt, self, other)
  }
}

///|
pub fn Expr::cmp_ge(self : Expr, other : Expr) -> Expr {
  self.cmp_lt(other).not()
}

///|
pub fn Expr::cmp_ge_i32(self : Expr, i32 : Int) -> Expr {
  self.cmp_ge(I32(i32))
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
pub fn Expr::sel(self : Expr, if_true : Expr, if_false : Expr) -> Expr {
  match self {
    Bin(true) => if_true
    Bin(false) => if_false
    self => Sel(self, if_true, if_false)
  }
}

///|
pub fn Expr::for_(self : Int, length : Int, body : Expr) -> Expr {
  For(self, length, body)
}

///|
pub impl Show for Expr with output(self : Expr, logger : &Logger) -> Unit {
  match self {
    Bin(true) => logger.write_string("true")
    Bin(false) => logger.write_string("false")
    I32(int) => logger.write_string(int.to_string())
    Var(var) => var.output(logger)
    Add(a, b) => logger.write_string("\{a} + \{b}")
    Sub(a, b) => logger.write_string("\{a} - \{b}")
    Mul(a, b) => logger.write_string("\{a} * \{b}")
    Div(a, b) => logger.write_string("\{a} / \{b}")
    Mod(a, b) => logger.write_string("\{a} % \{b}")
    Get(x, i) => logger.write_string("\{x}[\{i}]")
    Set(x, i, v) => logger.write_string("\{x}[\{i}] = \{v}")
    Cmp(Lt, a, b) => logger.write_string("\{a} < \{b}")
    Not(a) => logger.write_string("!\{a}")
    Sel(cond, if_true, if_false) =>
      logger.write_string("if \{cond} \{if_true} else \{if_false}")
    Let(var, expr, body) => {
      logger.write_string("let tmp_\{var} = \{expr} in")
      logger.write_string("\{body}")
    }
    Mut(var, expr) => logger.write_string("tmp_\{var} = \{expr}")
    Seq(a, b) => logger.write_string("\{a}\n\{b}")
    For(var, len, expr) => {
      logger.write_string("for tmp_\{var} in 0..\{len} {\n")
      logger.write_string("  \{expr}\n")
      logger.write_string("}")
    }
  }
}

///|
pub impl ToJson for Expr with to_json(self : Expr) -> Json {
  match self {
    Bin(true) => Json::True
    Bin(false) => Json::False
    I32(i32) => Json::Number(i32.to_double())
    Var(var) => var.to_string().to_json()
    Add(a, b) => { "add": [a.to_json(), b.to_json()] }
    Sub(a, b) => { "sub": [a.to_json(), b.to_json()] }
    Mul(a, b) => { "mul": [a.to_json(), b.to_json()] }
    Div(a, b) => { "div": [a.to_json(), b.to_json()] }
    Mod(a, b) => { "mod": [a.to_json(), b.to_json()] }
    Get(a, b) => { "get": [a.to_json(), b.to_json()] }
    Set(a, b, c) => { "set": [a.to_json(), b.to_json(), c.to_json()] }
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
          "length": length.to_json(),
          "body": body.to_json(),
        },
      }
    Seq(a, b) => [a.to_json(), b.to_json()]
  }
}

///|
pub fn Expr::atomize(self : Expr) -> Expr {
  let mut tmps = 0
  let tmps_remap = []
  let tmps_cache : Map[Expr, Int] = Map::new()
  fn get_tmp(expr : Expr) -> Int {
    guard let None = tmps_cache[expr] else { Some(tmp_id) => tmp_id }
    let tmp_id = tmps
    tmps += 1
    tmps_cache[expr] = tmp_id
    tmp_id
  }

  fn let_tmp(expr : Expr, k : (Expr) -> Expr) -> Expr {
    guard let None = tmps_cache[expr] else {
      Some(tmp_id) => k(var(tmp(tmp_id)))
    }
    let tmp_id = get_tmp(expr)
    let tmp_var = var(tmp(tmp_id))
    return let_(tmp_id, expr, k(tmp_var))
  }

  fn map_tmp(tmp : Int, expr : Expr) -> Unit {
    while tmps_remap.length() < tmp + 1 {
      tmps_remap.push(None)
    }
    tmps_remap[tmp] = Some(expr)
  }

  fn id(expr : Expr) -> Expr {
    expr
  }

  fn atomize(expr : Expr, k : (Expr) -> Expr) -> Expr {
    match expr {
      I32(val) => k(i32(val))
      Bin(val) => k(bin(val))
      Var(Arg(id)) => k(var(arg(id)))
      Var(Tmp(id)) =>
        match tmps_remap[id] {
          None => abort("Tmp variable not found")
          Some(expr) => k(expr)
        }
      Var(Idx(id)) => k(var(idx(id)))
      Add(a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(add(a, b), k) }) })
      Sub(a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(sub(a, b), k) }) })
      Mul(a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(mul(a, b), k) }) })
      Div(a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(div(a, b), k) }) })
      Mod(a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(mod(a, b), k) }) })
      Get(a, b) => atomize(b, fn(b) { let_tmp(get(a, b), k) })
      Set(a, b, c) =>
        atomize(b, fn(b) { atomize(c, fn(c) { let_tmp(set(a, b, c), k) }) })
      Cmp(Lt, a, b) =>
        atomize(a, fn(a) { atomize(b, fn(b) { let_tmp(cmp_lt(a, b), k) }) })
      Not(a) => atomize(a, fn(a) { let_tmp(Expr::not(a), k) })
      Sel(cond, if_true, if_false) =>
        atomize(cond, fn(cond) {
          let sel_val = sel(cond, atomize(if_true, id), atomize(if_false, id))
          let_tmp(sel_val, k)
        })
      Let(var, expr, body) =>
        atomize(expr, fn(expr) {
          map_tmp(var, expr)
          k(atomize(body, id))
        })
    }
  }

  atomize(self, fn(expr) { expr })
}
