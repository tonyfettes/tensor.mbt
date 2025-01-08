///|
pub enum Type {
  I32
  F32
  Arr(Type, UInt)
} derive(Eq, Hash)

///|
pub let i32 : Type = I32

///|
pub let f32 : Type = F32

///|
pub fn Type::arr(ty : Type, len : UInt) -> Type {
  Arr(ty, len)
}

///|
pub impl Show for Type with output(self : Type, logger : &Logger) -> Unit {
  match self {
    I32 => logger.write_string("i32")
    F32 => logger.write_string("f32")
    Arr(ty, len) => {
      logger.write_string("array<")
      ty.output(logger)
      logger.write_string(", ")
      len.output(logger)
      logger.write_string(">")
    }
  }
}
