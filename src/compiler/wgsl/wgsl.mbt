///|
struct Wgsl {}

///|
pub trait ToWgsl {
  to_wgsl(Self) -> String
}

///|
pub impl ToWgsl for @type.Type with to_wgsl(self : @type.Type) -> String {
  match self {
    I32 => "i32"
    F32 => "f32"
  }
}

///|
pub impl ToWgsl for @expr.Var with to_wgsl(self : @expr.Var) -> String {
  match self {
    Arg(id) => "arg\{id}"
    Tmp(id) => "tmp\{id}"
    Idx(id) => "idx\{id}"
  }
}

///|
pub impl ToWgsl for @expr.Left with to_wgsl(self : @expr.Left) -> String {
  match self {
    Get(var, idx) => "\{var.to_wgsl()}[\{idx.to_wgsl()}]"
    Var(var) => var.to_wgsl()
  }
}

///|
pub impl ToWgsl for @expr.Expr with to_wgsl(self : @expr.Expr) -> String {
  match self {
    Var(var) => var.to_wgsl()
    Bin(bool) => bool.to_string()
    U32(u32) => "u32(\{u32.to_string()})"
    Add(lhs, rhs) => "\{lhs.to_wgsl()} + \{rhs.to_wgsl()}"
    Sub(lhs, rhs) => "\{lhs.to_wgsl()} - \{rhs.to_wgsl()}"
    Mul(lhs, rhs) => "\{lhs.to_wgsl()} * \{rhs.to_wgsl()}"
    Mod(lhs, rhs) => "\{lhs.to_wgsl()} % \{rhs.to_wgsl()}"
    Div(lhs, rhs) => "\{lhs.to_wgsl()} / \{rhs.to_wgsl()}"
    Get(var, idx) => "\{var.to_wgsl()}[\{idx.to_wgsl()}]"
    Set(left, right) => "\{left.to_wgsl()} = \{right.to_wgsl()}"
    Cmp(Lt, lhs, rhs) => "\{lhs.to_wgsl()} < \{rhs.to_wgsl()}"
    Not(expr) => "!\{expr.to_wgsl()}"
    Sel(cond, lhs, rhs) =>
      "if \{cond.to_wgsl()} { \{lhs.to_wgsl()}; } else { \{rhs.to_wgsl()}; }"
    Let(id, expr, body) => "let tmp\{id} = \{expr.to_wgsl()}; \{body.to_wgsl()}"
    Mut(id, expr, body) => "var tmp\{id} = \{expr.to_wgsl()}; \{body.to_wgsl()}"
    For(id, end, body) =>
      "for (var tmp\{id} = u32(0); tmp\{id} < \{end}; tmp\{id}++) { \{body.to_wgsl()}; }"
    Seq(lhs, rhs) => "\{lhs.to_wgsl()}; \{rhs.to_wgsl()}"
  }
}

///|
pub impl ToWgsl for @kernel.Kernel with to_wgsl(self : @kernel.Kernel) -> String {
  let content = StringBuilder::new()
  for i, input in self.buffer() {
    content.write_string(
      $|@group(0) @binding(\{i + 1})
      $|var<storage, read_write> arg\{i + 1}: array<\{input.to_wgsl()}>;
      $|
      ,
    )
  }
  content.write_string(
    $|@compute
    $|fn main(
    $|  @builtin(global_invocation_id)
    $|  global_id : vec3u,
    $|) {
    $|  let idx0 = global_id.x;
    $|  \{self.kernel().to_wgsl()};
    $|}
    ,
  )
  content.to_string()
}
