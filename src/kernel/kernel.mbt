///|
struct Kernel {
  buffer : Array[@type.Type]
  kernel : @expr.Expr
}

///|
pub fn Kernel::buffer(self : Kernel) -> Array[@type.Type] {
  self.buffer
}

///|
pub fn Kernel::kernel(self : Kernel) -> @expr.Expr {
  self.kernel
}

///|
pub fn Kernel::new(buffer : Array[@type.Type], kernel : @expr.Expr) -> Kernel {
  Kernel::{ buffer, kernel }
}
