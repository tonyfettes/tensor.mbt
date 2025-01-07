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
enum Atom {
  Bin(Bool)
  I32(Int)
  Var(Var)
} derive(Eq, Hash)

///|
pub fn Atom::bin(bool : Bool) -> Atom {
  Bin(bool)
}

///|
pub fn Atom::i32(i32 : Int) -> Atom {
  I32(i32)
}

///|
pub fn Atom::var(var : Var) -> Atom {
  Var(var)
}

///|
priv enum Cmp {
  Lt
} derive(Eq, ToJson, Hash)

///|
enum Inst {
  Add(Atom, Atom)
  Sub(Atom, Atom)
  Mul(Atom, Atom)
  Div(Atom, Atom)
  Mod(Atom, Atom)
  Get(Atom, Atom)
  Cmp(Cmp, Atom, Atom)
  Not(Atom)
} derive(Eq, Hash)

///|
pub fn Inst::add(a : Atom, b : Atom) -> Inst {
  Add(a, b)
}

///|
pub fn Inst::sub(a : Atom, b : Atom) -> Inst {
  Sub(a, b)
}

///|
pub fn Inst::mul(a : Atom, b : Atom) -> Inst {
  Mul(a, b)
}

///|
pub fn Inst::div(a : Atom, b : Atom) -> Inst {
  Div(a, b)
}

///|
pub fn Inst::mod(a : Atom, b : Atom) -> Inst {
  Mod(a, b)
}

///|
pub fn Inst::get(a : Atom, b : Atom) -> Inst {
  Get(a, b)
}

///|
pub fn Inst::cmp_lt(a : Atom, b : Atom) -> Inst {
  Cmp(Lt, a, b)
}

///|
pub fn Inst::not(a : Atom) -> Inst {
  Not(a)
}

///|
enum Expr {
  Return(Atom)
  Let(Int, Inst, Expr)
  Select(Atom, Expr, Expr)
}

///|
pub fn Expr::let_(id : Int, inst : Inst, expr : Expr) -> Expr {
  Let(id, inst, expr)
}

///|
pub fn Expr::select(cond : Atom, then : Expr, else_ : Expr) -> Expr {
  Select(cond, then, else_)
}
