///|
enum Type {
  I32
  F32
  Ptr(Type)
} derive(Eq)

///|
pub let i32 : Type = Type::I32

///|
pub let ptr_i32 : Type = Type::Ptr(I32)

///|
pub let f32 : Type = Type::F32

///|
pub let ptr_f32 : Type = Type::Ptr(F32)

///|
pub impl Show for Type with output(self : Type, logger : &Logger) -> Unit {
  match self {
    I32 => logger.write_string("i32")
    F32 => logger.write_string("f32")
    Ptr(ty) => {
      logger.write_string("ptr(")
      ty.output(logger)
      logger.write_string(")")
    }
  }
}

pub impl ToJson for Type with to_json(self : Type) -> Json {
  match self {
    I32 => "i32"
    F32 => "f32"
    Ptr(self) => { "ptr": self.to_json() }
  }
}
