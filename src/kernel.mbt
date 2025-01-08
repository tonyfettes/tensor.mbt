///|
struct Kernel {
  params : Array[@type.Type]
  result : @type.Type
  shape : Array[Int]
  value : @expr.Expr
}

///|
impl Show for Kernel with output(self : Kernel, logger : &Logger) -> Unit {
  for i, p in self.params {
    logger.write_string("arg\{i}: ")
    p.output(logger)
    logger.write_char('\n')
  }
  logger.write_string("out: \{self.result}\n")
  logger.write_string("shape: \{self.shape}\n")
  self.value.output(logger)
}

///|
pub fn Kernel::params(self : Kernel) -> Array[@type.Type] {
  self.params
}

///|
pub fn Kernel::shape(self : Kernel) -> Array[Int] {
  self.shape
}

///|
pub fn Kernel::value(self : Kernel) -> @expr.Expr {
  self.value
}

///|
pub fn Kernel::new(
  params : Array[@type.Type],
  result : @type.Type,
  shape : Array[UInt],
  value : @expr.Expr
) -> Kernel {
  Kernel::{
    params,
    result,
    shape: shape.map(fn(s) { s.reinterpret_as_int() }),
    value,
  }
}
