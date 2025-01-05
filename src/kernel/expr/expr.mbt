///|
enum Var {
  Arg(Int)
  Tmp(Int)
  Idx(Int)
} derive(Eq)

///|
pub fn Var::arg(id : Int) -> Var {
  Arg(id)
}

///|
pub fn Var::idx(id : Int) -> Var {
  Idx(id)
}

///|
pub fn Var::tmp(id : Int) -> Var {
  Tmp(id)
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
} derive(Eq, ToJson)

///|
enum Expr {
  Bool(Bool)
  I32(Int)
  Var(Var)
  Add(Expr, Expr)
  Sub(Expr, Expr)
  Mul(Expr, Expr)
  Mod(Expr, Expr)
  Div(Expr, Expr)
  Get(Expr, Expr)
  Cmp(Cmp, Expr, Expr)
  Not(Expr)
  If(Expr, Expr, Expr)
  Let(Var, @type.Type, Expr, Expr)
} derive(Eq)

///|
pub fn Expr::i32(int : Int) -> Expr {
  I32(int)
}

///|
pub fn Expr::var(var : Var) -> Expr {
  Var(var)
}

///|
pub fn Expr::var_arg(id : Int) -> Expr {
  Var(Arg(id))
}

///|
pub fn Expr::var_idx(id : Int) -> Expr {
  Var(Idx(id))
}

///|
pub fn Expr::var_tmp(id : Int) -> Expr {
  Var(Tmp(id))
}

///|
pub fn Expr::get(self : Expr, index : Expr) -> Expr {
  Get(self, index)
}

///|
pub fn Expr::add(self : Expr, other : Expr) -> Expr {
  match (self, other) {
    (I32(self), I32(other)) => I32(self + other)
    (I32(0), other) => other
    (self, I32(0)) => self
    (Sub(a, b), c) => {
      if b == c {
        a
      } else {
        Add(Sub(a, b), c)
      }
    }
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
    (I32(self), I32(other)) => Bool(self < other)
    (self, other) => Cmp(Lt, self, other)
  }
}

///|
pub fn Expr::not(self : Expr) -> Expr {
  match self {
    Bool(self) => Bool(not(self))
    self => Not(self)
  }
}

///|
pub fn Expr::if_(self : Expr, if_true : Expr, if_false : Expr) -> Expr {
  match self {
    Bool(true) => if_true
    Bool(false) => if_false
    self => If(self, if_true, if_false)
  }
}

///|
pub fn Expr::if_ge(
  self : Expr,
  other : Expr,
  if_true : Expr,
  if_false : Expr
) -> Expr {
  if_(self.cmp_lt(other).not(), if_true, if_false)
}

///|
pub fn Expr::let_idx(id : Int, expr : Expr, body : Expr) -> Expr {
  Let(Idx(id), @type.i32, expr, body)
}

///|
pub fn Expr::let_tmp(id : Int, expr : Expr, body : Expr) -> Expr {
  Let(Tmp(id), @type.i32, expr, body)
}

///|
pub fn Expr::let_(var : Var, ty : @type.Type, expr : Expr, body : Expr) -> Expr {
  Let(var, ty, expr, body)
}

///|
pub fn Expr::subst(self : Expr, var : Var, expr : Expr) -> Expr {
  match self {
    Bool(_) | I32(_) => self
    Var(self_var) => if self_var == var { expr } else { self }
    Add(a, b) => Add(a.subst(var, expr), b.subst(var, expr))
    Sub(a, b) => Sub(a.subst(var, expr), b.subst(var, expr))
    Mul(a, b) => Mul(a.subst(var, expr), b.subst(var, expr))
    Div(a, b) => Div(a.subst(var, expr), b.subst(var, expr))
    Mod(a, b) => Mod(a.subst(var, expr), b.subst(var, expr))
    Get(x, i) => Get(x.subst(var, expr), i.subst(var, expr))
    Not(a) => Not(a.subst(var, expr))
    Cmp(op, a, b) => Cmp(op, a.subst(var, expr), b.subst(var, expr))
    If(cond, if_true, if_false) => {
      let cond = cond.subst(var, expr)
      let if_true = if_true.subst(var, expr)
      let if_false = if_false.subst(var, expr)
      If(cond, if_true, if_false)
    }
    Let(let_var, let_ty, let_expr, let_body) => {
      let let_expr = let_expr.subst(var, expr)
      if let_var == var {
        Let(let_var, let_ty, let_expr, let_body)
      } else {
        let let_body = let_body.subst(var, expr)
        Let(let_var, let_ty, let_expr, let_body)
      }
    }
  }
}

///|
impl Show for Expr with output(self : Expr, logger : &Logger) -> Unit {
  match self {
    Bool(true) => logger.write_string("true")
    Bool(false) => logger.write_string("false")
    I32(int) => logger.write_string(int.to_string())
    Var(var) => var.output(logger)
    Add(a, b) => logger.write_string("\{a} + \{b}")
    Sub(a, b) => logger.write_string("\{a} - \{b}")
    Mul(a, b) => logger.write_string("\{a} * \{b}")
    Div(a, b) => logger.write_string("\{a} / \{b}")
    Mod(a, b) => logger.write_string("\{a} % \{b}")
    Get(x, i) => logger.write_string("\{x}[\{i}]")
    Cmp(Lt, a, b) => logger.write_string("\{a} < \{b}")
    Not(a) => logger.write_string("!\{a}")
    If(cond, if_true, if_false) =>
      logger.write_string("if \{cond} \{if_true} else \{if_false}")
    Let(var, ty, expr, body) =>
      logger.write_string("let \{var} : \{ty} = \{expr} in \{body}")
  }
}

///|
pub impl ToJson for Expr with to_json(self : Expr) -> Json {
  match self {
    Bool(true) => Json::True
    Bool(false) => Json::False
    I32(i32) => Json::Number(i32.to_double())
    Var(var) => var.to_string().to_json()
    Add(a, b) => { "add": [a.to_json(), b.to_json()] }
    Sub(a, b) => { "sub": [a.to_json(), b.to_json()] }
    Mul(a, b) => { "mul": [a.to_json(), b.to_json()] }
    Div(a, b) => { "div": [a.to_json(), b.to_json()] }
    Mod(a, b) => { "mod": [a.to_json(), b.to_json()] }
    Get(a, b) => { "get": [a.to_json(), b.to_json()] }
    Cmp(Lt, a, b) => { "cmp": { "lt": [a.to_json(), b.to_json()] } }
    Not(a) => { "not": a.to_json() }
    If(cond, if_true, if_false) =>
      {
        "if": {
          "cond": cond.to_json(),
          "then": if_true.to_json(),
          "else": if_false.to_json(),
        },
      }
    Let(var, ty, expr, body) =>
      {
        "let": {
          "var": var.to_json(),
          "ty": ty.to_json(),
          "expr": expr.to_json(),
          "body": body.to_json(),
        },
      }
  }
}
